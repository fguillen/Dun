require "test_helper"

module MapGeneration
  class AssignLateJoinerTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace, seed: "0000000000002f35", min_players: 12)
      MapGeneration::Generate.call(world: @world, players_count: 12)
    end

    test "assigns the profile to an available spawn region and bootstraps the kingdom" do
      profile = create(:player_profile, server: @world.server)
      kingdom = AssignLateJoiner.call(world: @world, player_profile: profile, hours_since_t0: 12)

      assert kingdom.persisted?
      assert_not_nil kingdom.home_region_id
      assert_equal profile.id, kingdom.player_profile_id
      assert kingdom.home_region.spawn_eligible
      assert_equal 1_500, kingdom.reload.stockpile("gold")  # 500 base + 1000 12h bonus
    end

    test "two profiles get distinct spawn regions" do
      p1 = create(:player_profile, server: @world.server)
      p2 = create(:player_profile, server: @world.server)
      k1 = AssignLateJoiner.call(world: @world, player_profile: p1, hours_since_t0: 0)
      k2 = AssignLateJoiner.call(world: @world, player_profile: p2, hours_since_t0: 0)
      refute_equal k1.home_region_id, k2.home_region_id
    end

    test "an existing kingdom is bootstrapped without changing home_region" do
      profile = create(:player_profile, server: @world.server)
      first = AssignLateJoiner.call(world: @world, player_profile: profile, hours_since_t0: 0)
      second = AssignLateJoiner.call(world: @world, player_profile: profile, hours_since_t0: 24)
      assert_equal first.id, second.id
      assert_equal first.home_region_id, second.home_region_id
    end

    test "raises NoSpawnSlotAvailable when all reserved slots are claimed" do
      available = @world.regions.where(spawn_eligible: true).count
      available.times do
        AssignLateJoiner.call(
          world: @world,
          player_profile: create(:player_profile, server: @world.server),
          hours_since_t0: 0
        )
      end
      profile = create(:player_profile, server: @world.server)
      assert_raises(AssignLateJoiner::NoSpawnSlotAvailable) do
        AssignLateJoiner.call(world: @world, player_profile: profile, hours_since_t0: 0)
      end
    end
  end
end
