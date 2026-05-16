module Rounds
  # Round-end critical path. Replaces Phase 9's inline world archival in
  # Wonders::Complete with the full §16.6 + §17.4 flow: world archived,
  # frozen state snapshot persisted, per-player stats incremented, winner
  # titled, leaderboards recomputed.
  class End
    def self.call(world:, winning_kingdom: nil, wonder_name: nil, at: Time.current)
      new(world: world, winning_kingdom: winning_kingdom, wonder_name: wonder_name, at: at).call
    end

    def initialize(world:, winning_kingdom:, wonder_name:, at:)
      @world = world
      @winning_kingdom = winning_kingdom
      @wonder_name = wonder_name
      @at = at
    end

    def call
      ActiveRecord::Base.transaction do
        world = World.lock.find(@world.id)
        return world if world.archived?

        world.update!(
          status: "archived",
          archived_at: @at,
          winner_kingdom_id: @winning_kingdom&.id,
          wonder_name: @wonder_name
        )

        archive_row(world)
        increment_round_stats(world)
        award_winner_title(world)
        Leaderboards::Recompute.call(server: world.server, now: @at)

        ActiveSupport::Notifications.instrument(
          "dun.round.ended",
          world_id: world.id,
          winner_kingdom_id: @winning_kingdom&.id,
          wonder_name: @wonder_name
        )

        ActiveSupport::Notifications.instrument(
          "dun.world.archived",
          world_id: world.id,
          winner_kingdom_id: @winning_kingdom&.id,
          wonder_name: @wonder_name
        )

        world
      end
    end

    private

    def archive_row(world)
      frozen = Rounds::SnapshotState.call(world, ended_at: @at)
      RoundArchive.create!(
        world_id: world.id,
        winner_kingdom_id: @winning_kingdom&.id,
        wonder_name: @wonder_name,
        frozen_state: frozen,
        ended_at: @at
      )
    end

    def increment_round_stats(world)
      world.kingdoms.includes(player_profile: :stats).find_each do |kingdom|
        profile = kingdom.player_profile
        next if profile.nil?
        Profiles::Increment.call(player_profile: profile, deltas: { rounds_played: 1 })
        Profiles::MaxPeakNodes.call(player_profile: profile, candidate: kingdom.peak_nodes)
      end
    end

    def award_winner_title(world)
      return if @winning_kingdom.nil?
      profile = @winning_kingdom.player_profile
      return if profile.nil?

      Profiles::Increment.call(player_profile: profile, deltas: { rounds_won: 1, wonders_completed: 1 })
      Titles::Award.call(player_profile: profile, world: world, at: @at)
    end
  end
end
