module Worlds
  class Join
    class WorldNotJoinable < StandardError; end
    class ServerAccessDenied < StandardError; end
    class NotServerMember < StandardError; end
    class WorldAccountLimitReached < StandardError; end

    def self.call(world:, player:)
      new(world: world, player: player).call
    end

    def initialize(world:, player:)
      @world = world
      @player = player
    end

    def call
      raise WorldNotJoinable, "world is #{@world.status}; not joinable" unless @world.joinable?
      raise ServerAccessDenied, "player not admitted to server" unless @world.server.admits?(@player.email)
      raise NotServerMember, "player has not joined the server" unless server_member?

      enforce_world_account_limit!

      ActiveRecord::Base.transaction do
        profile = PlayerProfile.find_or_create_by!(server: @world.server, player: @player)

        if @world.proposed?
          @world.kingdoms.create_with(joined_at: Time.current).find_or_create_by!(player_profile: profile)
        else
          hours_since_t0 = ((Time.current - @world.t0_at) / 1.hour).floor
          MapGeneration::AssignLateJoiner.call(world: @world, player_profile: profile, hours_since_t0: hours_since_t0)
        end
      end
    end

    private

    def server_member?
      @world.server.server_memberships.exists?(player_id: @player.id)
    end

    def enforce_world_account_limit!
      limit = @world.server.max_worlds_per_account
      return if limit.zero?

      current = Kingdom
        .joins(:world, player_profile: { })
        .where(player_profiles: { player_id: @player.id, server_id: @world.server_id })
        .where(worlds: { status: World::LIVE_STATUSES })
        .count
      return if current < limit

      raise WorldAccountLimitReached, "player already participates in #{current} worlds on this server (limit #{limit})"
    end
  end
end
