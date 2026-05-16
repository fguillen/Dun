module Leaderboards
  # Recomputes all four per-server leaderboard snapshots. Called only at
  # round end (§17.4). Each snapshot row is replaced atomically.
  class Recompute
    TOP_N = 10

    KIND_ORDERS = {
      "champions" => { primary: :rounds_won,        secondary: :wonders_destroyed },
      "wreckers"  => { primary: :wonders_destroyed, secondary: :rounds_won },
      "warlords"  => { primary: :peak_nodes,        secondary: :rounds_won },
      "veterans"  => { primary: :rounds_played,    secondary: :rounds_won }
    }.freeze

    def self.call(server:, now: Time.current)
      new(server: server, now: now).call
    end

    def initialize(server:, now:)
      @server = server
      @now = now
    end

    def call
      ActiveRecord::Base.transaction do
        KIND_ORDERS.each do |kind, cols|
          entries = compute_entries(cols[:primary], cols[:secondary])
          snapshot = LeaderboardSnapshot.find_or_initialize_by(server_id: @server.id, kind: kind)
          snapshot.snapshot_at = @now
          snapshot.entries = entries
          snapshot.save!
        end
      end
      LeaderboardSnapshot.where(server_id: @server.id)
    end

    private

    def compute_entries(primary, secondary)
      PlayerProfileStats
        .joins(:player_profile)
        .where(player_profiles: { server_id: @server.id })
        .where("#{primary} > 0")
        .order(Arel.sql("#{primary} DESC, #{secondary} DESC, player_profile_stats.created_at ASC"))
        .limit(TOP_N)
        .pluck(
          :player_profile_id,
          "player_profiles.handle",
          primary,
          secondary
        )
        .map do |profile_id, handle, score, sec|
          {
            "player_profile_id" => profile_id,
            "handle" => handle,
            "score" => score,
            "secondary" => sec
          }
        end
    end
  end
end
