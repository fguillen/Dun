require "test_helper"

module Leaderboards
  class RecomputeTest < ActiveSupport::TestCase
    setup do
      @server = create(:server)
    end

    def stat_profile(handle:, **attrs)
      profile = create(:player_profile, server: @server, handle: handle)
      profile.stats.update!(attrs)
      profile
    end

    test "creates one snapshot per kind, sorted correctly" do
      stat_profile(handle: "alice", rounds_won: 3, wonders_destroyed: 1, peak_nodes: 5, rounds_played: 4)
      stat_profile(handle: "bob",   rounds_won: 2, wonders_destroyed: 4, peak_nodes: 1, rounds_played: 6)
      stat_profile(handle: "cara",  rounds_won: 0, wonders_destroyed: 0, peak_nodes: 9, rounds_played: 2)

      Recompute.call(server: @server)

      kinds = LeaderboardSnapshot.where(server_id: @server.id).pluck(:kind).sort
      assert_equal LeaderboardSnapshot::KINDS.sort, kinds

      champions = LeaderboardSnapshot.find_by!(server_id: @server.id, kind: "champions")
      assert_equal [ "alice", "bob" ], champions.entries.map { |e| e["handle"] }

      wreckers = LeaderboardSnapshot.find_by!(server_id: @server.id, kind: "wreckers")
      assert_equal [ "bob", "alice" ], wreckers.entries.map { |e| e["handle"] }

      warlords = LeaderboardSnapshot.find_by!(server_id: @server.id, kind: "warlords")
      assert_equal [ "cara", "alice", "bob" ], warlords.entries.map { |e| e["handle"] }

      veterans = LeaderboardSnapshot.find_by!(server_id: @server.id, kind: "veterans")
      assert_equal [ "bob", "alice", "cara" ], veterans.entries.map { |e| e["handle"] }
    end

    test "replaces existing snapshots on re-run" do
      profile = stat_profile(handle: "alice", rounds_won: 1)
      Recompute.call(server: @server)
      original_at = LeaderboardSnapshot.find_by!(server_id: @server.id, kind: "champions").snapshot_at

      profile.stats.update!(rounds_won: 5)
      travel 1.second
      Recompute.call(server: @server)

      snap = LeaderboardSnapshot.find_by!(server_id: @server.id, kind: "champions")
      assert_equal 5, snap.entries.first["score"]
      assert snap.snapshot_at > original_at
    end

    test "caps entries at TOP_N" do
      12.times { |i| stat_profile(handle: "Player#{i.to_s.rjust(2, '0')}", rounds_won: i + 1) }
      Recompute.call(server: @server)
      snap = LeaderboardSnapshot.find_by!(server_id: @server.id, kind: "champions")
      assert_equal Recompute::TOP_N, snap.entries.size
    end
  end
end
