require "test_helper"

module Rounds
  class EndTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @winner_profile = create(:player_profile, server: @world.server)
      @loser_profile = create(:player_profile, server: @world.server)
      @winner = create(:kingdom, world: @world, player_profile: @winner_profile, home_region: @region, peak_nodes: 4)
      @loser = create(:kingdom, world: @world, player_profile: @loser_profile, home_region: @region, peak_nodes: 2)
    end

    test "archives the world, snapshots state, increments stats, awards title, recomputes leaderboards" do
      events = []
      ActiveSupport::Notifications.subscribed(->(name, _, _, _, p) { events << [ name, p ] }, /dun\.(round|world)\./) do
        End.call(world: @world, winning_kingdom: @winner, wonder_name: "sky_tower")
      end

      @world.reload
      assert_equal "archived", @world.status
      assert_equal @winner.id, @world.winner_kingdom_id
      assert_equal "sky_tower", @world.wonder_name
      assert_not_nil @world.archived_at

      archive = @world.round_archive
      assert_not_nil archive
      assert_equal @winner.id, archive.winner_kingdom_id
      assert_equal "sky_tower", archive.wonder_name
      assert archive.frozen_state["kingdoms"].is_a?(Array)
      assert_equal 2, archive.frozen_state["kingdoms"].size

      @winner_profile.stats.reload
      @loser_profile.stats.reload
      assert_equal 1, @winner_profile.stats.rounds_played
      assert_equal 1, @winner_profile.stats.rounds_won
      assert_equal 1, @winner_profile.stats.wonders_completed
      assert_equal 4, @winner_profile.stats.peak_nodes
      assert_equal 1, @loser_profile.stats.rounds_played
      assert_equal 0, @loser_profile.stats.rounds_won
      assert_equal 2, @loser_profile.stats.peak_nodes

      assert_equal 1, @winner_profile.titles.where(kind: "champion", world_id: @world.id).count

      assert LeaderboardSnapshot.where(server_id: @world.server_id).exists?

      kinds = events.map(&:first)
      assert_includes kinds, "dun.round.ended"
      assert_includes kinds, "dun.world.archived"
    end

    test "is idempotent on re-call" do
      End.call(world: @world, winning_kingdom: @winner, wonder_name: "sky_tower")
      assert_no_difference -> { RoundArchive.count } do
        End.call(world: @world, winning_kingdom: @winner, wonder_name: "sky_tower")
      end
      @winner_profile.stats.reload
      assert_equal 1, @winner_profile.stats.rounds_played
    end

    test "per-server scoping: same player on two servers gets independent stats" do
      other_server = create(:server)
      other_world = create(:world, :active, server: other_server)
      other_region = create(:region, world: other_world)
      shared_player = @winner_profile.player
      other_profile = create(:player_profile, server: other_server, player: shared_player)
      create(:kingdom, world: other_world, player_profile: other_profile, home_region: other_region, peak_nodes: 0)

      End.call(world: @world, winning_kingdom: @winner, wonder_name: "sky_tower")

      assert_equal 1, @winner_profile.stats.reload.rounds_played
      assert_equal 0, other_profile.stats.reload.rounds_played
    end
  end
end
