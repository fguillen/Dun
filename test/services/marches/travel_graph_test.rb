require "test_helper"

module Marches
  class TravelGraphTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace)
      @plains = create(:region, world: @world, terrain: "plains", name: "Plains")
      @mountain = create(:region, world: @world, terrain: "mountain", name: "Mountain")
      @hills = create(:region, world: @world, terrain: "hills", name: "Hills")
      @isolated = create(:region, world: @world, terrain: "plains", name: "Isolated")
      RegionAdjacency.connect(@plains, @mountain)
      RegionAdjacency.connect(@mountain, @hills)
    end

    test "adjacency_for builds an undirected map" do
      adjacency = TravelGraph.adjacency_for(@world)
      assert_equal [ @mountain.id ], adjacency[@plains.id]
      assert_equal [ @plains.id, @hills.id ].sort, adjacency[@mountain.id].sort
      assert_empty adjacency[@isolated.id]
    end

    test "shortest_paths_from maps the origin to nil and omits unreachable nodes" do
      preds = TravelGraph.shortest_paths_from(@plains.id, TravelGraph.adjacency_for(@world))
      assert_nil preds[@plains.id]
      assert_equal @plains.id, preds[@mountain.id]
      assert_equal @mountain.id, preds[@hills.id]
      assert_not preds.key?(@isolated.id)
    end

    test "path_to reconstructs origin..target, nil when unreachable" do
      preds = TravelGraph.shortest_paths_from(@plains.id, TravelGraph.adjacency_for(@world))
      assert_equal [ @plains.id, @mountain.id, @hills.id ], TravelGraph.path_to(preds, @hills.id)
      assert_equal [ @plains.id ], TravelGraph.path_to(preds, @plains.id)
      assert_nil TravelGraph.path_to(preds, @isolated.id)
    end

    test "terrain_avg averages endpoint modifiers, or 1.0 when immune" do
      assert_in_delta 1.0, TravelGraph.terrain_avg(@plains, @plains, false), 1e-9
      assert_in_delta 0.8, TravelGraph.terrain_avg(@plains, @mountain, false), 1e-9
      assert_in_delta 1.0, TravelGraph.terrain_avg(@plains, @mountain, true), 1e-9
    end

    test "leg_seconds follows speed × terrain formula" do
      # speed 0.5, plains→mountain avg 0.8 → 1 / (0.5 * 0.8) h = 2.5h
      assert_in_delta 2.5 * 3600, TravelGraph.leg_seconds(@plains, @mountain, 0.5, false), 1e-6
      # immune ignores terrain: 1 / (1.0 * 1.0) h = 1h
      assert_in_delta 3600, TravelGraph.leg_seconds(@plains, @mountain, 1.0, true), 1e-6
    end
  end
end
