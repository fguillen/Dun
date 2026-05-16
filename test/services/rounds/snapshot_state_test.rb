require "test_helper"

module Rounds
  class SnapshotStateTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @profile = create(:player_profile, server: @world.server)
      @kingdom = create(:kingdom, :with_buildings, world: @world, player_profile: @profile, home_region: @region)
    end

    test "contains regions, kingdoms, ended_at, and zero counts when nothing happened" do
      state = SnapshotState.call(@world)
      assert_kind_of String, state["ended_at"]
      assert_equal 1, state["regions"].size
      assert_equal 1, state["kingdoms"].size
      assert_equal 0, state["battles_count"]
      assert_equal 0, state["caravans_count"]
      assert_nil state["wonder"]
    end

    test "includes the live wonder if one exists" do
      create(:wonder, kingdom: @kingdom, name: "sky_tower", status: "construction", hp: 1234)
      state = SnapshotState.call(@world)
      assert_equal "sky_tower", state["wonder"]["name"]
      assert_equal 1234, state["wonder"]["hp"]
    end
  end
end
