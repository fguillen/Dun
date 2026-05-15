require "test_helper"

module Marches
  class PlanTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace)
      @plains = create(:region, world: @world, terrain: "plains", name: "Plains")
      @mountain = create(:region, world: @world, terrain: "mountain", name: "Mountain")
      @hills = create(:region, world: @world, terrain: "hills", name: "Hills")
      RegionAdjacency.connect(@plains, @mountain)
      RegionAdjacency.connect(@mountain, @hills)

      kingdom = create(:kingdom, world: @world, home_region: @plains)
      @mixed = create(:army, kingdom: kingdom, location_region: @plains,
        composition: { "knight" => 100, "levy" => 200 })
      @knights = create(:army, kingdom: kingdom, location_region: @plains, name: "Cavalry",
        composition: { "knight" => 100 })
    end

    test "matches §16.10 worked example for mixed Knight + Levy across Plains→Mountain→Hills" do
      result = Plan.call(origin: @plains, destination: @hills, army: @mixed)
      # leg1: avg = (1.0 + 0.6) / 2 = 0.8; t = 1 / (0.5 * 0.8) = 2.5h
      # leg2: avg = (0.6 + 0.9) / 2 = 0.75; t = 1 / (0.5 * 0.75) = 2.6667h
      expected = (2.5 + 1.0 / (0.5 * 0.75)) * 3600
      assert_in_delta expected, result.total_seconds, 1.0
      assert_equal [ @plains.id, @mountain.id, @hills.id ], result.path
    end

    test "Knight-only army ignores terrain (§16.10) — total = hops × 1h at speed 1" do
      result = Plan.call(origin: @plains, destination: @hills, army: @knights)
      assert_in_delta 2 * 3600, result.total_seconds, 1.0
      result.per_leg.each { |leg| assert_equal 1.0, leg.terrain_avg }
    end

    test "single-region path = 0 legs, 0 seconds" do
      result = Plan.call(origin: @plains, destination: @plains, army: @mixed)
      assert_equal [ @plains.id ], result.path
      assert_equal 0.0, result.total_seconds
    end

    test "raises EmptyArmy" do
      empty = create(:army, kingdom: @mixed.kingdom, location_region: @plains, name: "Skeleton",
        composition: {})
      assert_raises(Plan::EmptyArmy) do
        Plan.call(origin: @plains, destination: @hills, army: empty)
      end
    end

    test "raises CrossWorld when origin/destination are in different worlds" do
      other_world = create(:world, :grace)
      other_region = create(:region, world: other_world)
      assert_raises(Plan::CrossWorld) do
        Plan.call(origin: @plains, destination: other_region, army: @mixed)
      end
    end

    test "raises Unreachable when no adjacency path exists" do
      isolated = create(:region, world: @world, name: "Isolated")
      assert_raises(Plan::Unreachable) do
        Plan.call(origin: @plains, destination: isolated, army: @mixed)
      end
    end

    test "mixed army loses terrain immunity (slowest unit dictates the formula)" do
      mixed = create(:army, kingdom: @mixed.kingdom, location_region: @plains, name: "Hybrid",
        composition: { "knight" => 1, "scout" => 1, "levy" => 1 })
      result = Plan.call(origin: @plains, destination: @mountain, army: mixed)
      # Slowest = levy (0.5), terrain avg = (1.0 + 0.6) / 2 = 0.8 → 1/(0.5*0.8) = 2.5h
      assert_in_delta 2.5 * 3600, result.total_seconds, 1.0
    end
  end
end
