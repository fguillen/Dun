require "test_helper"

module MapGeneration
  class PlaceRuinsTest < ActiveSupport::TestCase
    GOOD_SEEDS = {
      4  => "0000000000000fe4",
      8  => "0000000000001fd9",
      12 => "0000000000002f35",
      16 => "0000000000003fc3"
    }.freeze

    def build_world_through_nodes(players: 12, seed: nil)
      seed ||= GOOD_SEEDS.fetch(players)
      world = create(:world, seed: seed)
      rng = Random.new(world.seed_int)
      BuildGraph.call(world: world, players_count: players, rng: rng)
      AssignTerrain.call(world: world, rng: rng)
      PlaceSpawns.call(world: world, players_count: players, rng: rng)
      PlaceNodes.call(world: world, players_count: players, rng: rng)
      [ world, rng ]
    end

    test "ruin count caps at max(2, round(players / 4)) per \u00a716.11" do
      [ [ 4, 2 ], [ 8, 2 ], [ 12, 3 ], [ 16, 4 ] ].each do |players, expected|
        world, rng = build_world_through_nodes(players: players)
        ruins = PlaceRuins.call(world: world, players_count: players, rng: rng)
        assert ruins.size <= expected, "expected at most #{expected} ruins for #{players} players, got #{ruins.size}"
      end
    end

    test "16-player maps fit the full ruin allotment" do
      world, rng = build_world_through_nodes(players: 16)
      ruins = PlaceRuins.call(world: world, players_count: 16, rng: rng)
      assert ruins.size >= 2, "expected >=2 ruins, got #{ruins.size}"
    end

    test "no ruin is placed on mountain or marsh" do
      world, rng = build_world_through_nodes(players: 16)
      PlaceRuins.call(world: world, players_count: 16, rng: rng)
      world.reload.ruins.includes(:region).each do |r|
        refute_includes %w[mountain marsh], r.region.terrain, "ruin on excluded terrain #{r.region.terrain}"
      end
    end

    test "no ruin shares a region with a node" do
      world, rng = build_world_through_nodes(players: 16)
      PlaceRuins.call(world: world, players_count: 16, rng: rng)
      node_regions = world.nodes.pluck(:region_id).to_set
      world.reload.ruins.each do |r|
        refute node_regions.include?(r.region_id), "ruin shares a region with a node"
      end
    end

    test "ruins are at least 2 hops apart" do
      world, rng = build_world_through_nodes(players: 16)
      PlaceRuins.call(world: world, players_count: 16, rng: rng)
      ids = world.ruins.pluck(:region_id)
      adjacency = build_adj(world)
      ids.each_with_index do |a, i|
        ids[(i + 1)..].each do |b|
          dist = bfs_min_dist(a, [ b ], adjacency)
          assert dist >= 2, "ruins #{a} and #{b} are #{dist} hops apart"
        end
      end
    end

    test "tier garrison and cache match the \u00a716.11 tables" do
      world, rng = build_world_through_nodes(players: 16)
      PlaceRuins.call(world: world, players_count: 16, rng: rng)
      world.ruins.each do |r|
        assert_equal Ruin::GARRISONS[r.tier].deep_stringify_keys, r.garrison
        assert_equal Ruin::CACHES[r.tier].deep_stringify_keys, r.cache
      end
    end

    test "same seed reproduces identical ruin placement" do
      a, rng_a = build_world_through_nodes(players: 12)
      PlaceRuins.call(world: a, players_count: 12, rng: rng_a)

      b, rng_b = build_world_through_nodes(players: 12)
      PlaceRuins.call(world: b, players_count: 12, rng: rng_b)

      a_sig = a.ruins.includes(:region).map { |r| [ r.region.name, r.tier ] }.sort
      b_sig = b.ruins.includes(:region).map { |r| [ r.region.name, r.tier ] }.sort
      assert_equal a_sig, b_sig
    end

    private

    def build_adj(world)
      ids = world.regions.pluck(:id)
      map = ids.each_with_object({}) { |id, h| h[id] = [] }
      RegionAdjacency.where(region_a_id: ids).each do |a|
        map[a.region_a_id] << a.region_b_id
        map[a.region_b_id] << a.region_a_id
      end
      map
    end

    def bfs_min_dist(start_id, target_ids, adjacency)
      return Float::INFINITY if target_ids.empty?

      target_set = target_ids.to_set
      seen = { start_id => 0 }
      frontier = [ start_id ]
      depth = 0
      until frontier.empty?
        depth += 1
        nxt = []
        frontier.each do |id|
          adjacency[id].each do |n|
            next if seen.key?(n)
            return depth if target_set.include?(n)
            seen[n] = depth
            nxt << n
          end
        end
        frontier = nxt
      end
      Float::INFINITY
    end
  end
end
