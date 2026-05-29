require "test_helper"

module Marches
  class BulkPreviewTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace)
      @plains = create(:region, world: @world, terrain: "plains", name: "Plains")
      @mountain = create(:region, world: @world, terrain: "mountain", name: "Mountain")
      @hills = create(:region, world: @world, terrain: "hills", name: "Hills")
      @isolated = create(:region, world: @world, terrain: "plains", name: "Isolated")
      RegionAdjacency.connect(@plains, @mountain)
      RegionAdjacency.connect(@mountain, @hills)

      @kingdom = create(:kingdom, world: @world, home_region: @plains)
      @mixed = create(:army, kingdom: @kingdom, location_region: @plains, name: "Vanguard",
        composition: { "knight" => 100, "levy" => 200 })
    end

    def regions_for(result, army_id)
      preview = result[:army_previews].find { |p| p[:army_id] == army_id }
      preview[:regions].index_by { |r| r[:region_id] }
    end

    test "one preview per owned army, one region entry per world region" do
      create(:army, kingdom: @kingdom, location_region: @plains, name: "Second",
        composition: { "scout" => 5 })
      result = BulkPreview.call(kingdom: @kingdom)

      assert_equal 2, result[:army_previews].size
      result[:army_previews].each do |preview|
        assert_equal @world.regions.count, preview[:regions].size
      end
    end

    test "army's current region is reachable with 0 hops and 0 duration" do
      regions = regions_for(BulkPreview.call(kingdom: @kingdom), @mixed.id)
      origin = regions[@plains.id]
      assert origin[:reachable]
      assert_equal 0, origin[:hops]
      assert_equal 0, origin[:duration_seconds]
    end

    test "reachable region reports hops, duration matching Marches::Plan, and arrives_at" do
      regions = regions_for(BulkPreview.call(kingdom: @kingdom), @mixed.id)
      hills = regions[@hills.id]
      plan = Plan.call(origin: @plains, destination: @hills, army: @mixed)

      assert hills[:reachable]
      assert_equal 2, hills[:hops]
      assert_equal plan.total_seconds.round, hills[:duration_seconds]
      assert_not_nil hills[:arrives_at]
    end

    test "unreachable region reports reachable: false with no duration" do
      regions = regions_for(BulkPreview.call(kingdom: @kingdom), @mixed.id)
      isolated = regions[@isolated.id]
      assert_equal false, isolated[:reachable]
      assert_not isolated.key?(:duration_seconds)
      assert_not isolated.key?(:arrives_at)
    end

    test "empty army is unreachable everywhere" do
      empty = create(:army, kingdom: @kingdom, location_region: @plains, name: "Skeleton",
        composition: {})
      regions = regions_for(BulkPreview.call(kingdom: @kingdom), empty.id)
      assert regions.values.all? { |r| r[:reachable] == false }
    end

    test "terrain-immune army ignores terrain (1h per hop at speed 1)" do
      knights = create(:army, kingdom: @kingdom, location_region: @plains, name: "Cavalry",
        composition: { "knight" => 10 })
      regions = regions_for(BulkPreview.call(kingdom: @kingdom), knights.id)
      assert_equal 2 * 3600, regions[@hills.id][:duration_seconds]
    end

    test "kingdom with no armies returns an empty list" do
      empty_kingdom = create(:kingdom, world: @world,
        player_profile: create(:player_profile, server: @world.server))
      assert_equal({ army_previews: [] }, BulkPreview.call(kingdom: empty_kingdom))
    end
  end
end
