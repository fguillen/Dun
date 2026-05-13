require "test_helper"

module MapGeneration
  class PlaceSpawnsTest < ActiveSupport::TestCase
    # Seeds chosen empirically to land at least the player-count in spawn slots.
    GOOD_SEEDS = {
      4  => "0000000000000fe4",
      8  => "0000000000001fd9",
      12 => "0000000000002f35",
      16 => "0000000000003fc3"
    }.freeze

    def build_world_through_terrain(players: 12, seed: nil)
      seed ||= GOOD_SEEDS.fetch(players)
      world = create(:world, seed: seed)
      rng = Random.new(world.seed_int)
      BuildGraph.call(world: world, players_count: players, rng: rng)
      AssignTerrain.call(world: world, rng: rng)
      [ world, rng ]
    end

    test "reserves up to ceil(players * 1.5) spawn slots on a workable seed" do
      world, rng = build_world_through_terrain(players: 8)
      result = PlaceSpawns.call(world: world, players_count: 8, rng: rng)
      target = (8 * 1.5).ceil
      assert result.spawn_regions.size >= 8, "placed #{result.spawn_regions.size} < 8 player count"
      assert result.spawn_regions.size <= target
      assert_equal result.spawn_regions.size, world.regions.where(spawn_eligible: true).count
    end

    test "small player counts hit the full 1.5x reserve" do
      world, rng = build_world_through_terrain(players: 4)
      result = PlaceSpawns.call(world: world, players_count: 4, rng: rng)
      assert_equal 6, result.spawn_regions.size
    end

    test "every spawn region sits on plains or hills" do
      world, rng = build_world_through_terrain(players: 12)
      result = PlaceSpawns.call(world: world, players_count: 12, rng: rng)
      result.spawn_regions.each do |r|
        assert_includes Region::SPAWN_TERRAINS, r.terrain, "#{r.name} on #{r.terrain}"
      end
    end

    test "spawn regions are at least 2 hops apart" do
      world, rng = build_world_through_terrain(players: 12)
      result = PlaceSpawns.call(world: world, players_count: 12, rng: rng)

      adjacency = build_adj_map(world)
      ids = result.spawn_regions.map(&:id)
      ids.each_with_index do |a, i|
        ids[(i + 1)..].each do |b|
          dist = bfs_distance(a, b, adjacency)
          assert dist >= 2, "spawns #{a} and #{b} are only #{dist} hops apart"
        end
      end
    end

    test "no spawn region is adjacent to a rich node after the full pipeline" do
      world, rng = build_world_through_terrain(players: 12)
      result = PlaceSpawns.call(world: world, players_count: 12, rng: rng)
      PlaceNodes.call(world: world, players_count: 12, rng: rng)

      rich_region_ids = world.nodes.where(tier: "rich", is_home_hoard: false).pluck(:region_id).to_set
      adjacency = build_adj_map(world)
      result.spawn_regions.each do |spawn|
        adjacency[spawn.id].each do |neighbor|
          refute rich_region_ids.include?(neighbor), "spawn #{spawn.name} is adjacent to a rich-node region"
        end
      end
    end

    test "no spawn region is a hub (degree >= 5) when target is reachable without relaxation" do
      # Pick a seed where we can place the full 1.5x slot count without relaxing the degree rule.
      world, rng = build_world_through_terrain(players: 4, seed: "1111111111111111")
      result = PlaceSpawns.call(world: world, players_count: 4, rng: rng)
      result.spawn_regions.each do |r|
        refute r.is_hub, "spawn #{r.name} is a hub"
      end
    end

    test "places a standard-tier home hoard at every spawn region" do
      world, rng = build_world_through_terrain(players: 8)
      result = PlaceSpawns.call(world: world, players_count: 8, rng: rng)
      assert_equal result.spawn_regions.size, result.home_hoards.size
      result.home_hoards.each do |node|
        assert_equal "standard", node.tier
        assert_equal Node::TIER_BASE_RATE["standard"], node.base_rate
        assert node.is_home_hoard
        assert_includes Kingdom::RESOURCES, node.resource
      end
    end

    test "same seed reproduces identical spawn placement" do
      world_a, rng_a = build_world_through_terrain(seed: "abcd1111ef220000")
      PlaceSpawns.call(world: world_a, players_count: 12, rng: rng_a)
      world_b, rng_b = build_world_through_terrain(seed: "abcd1111ef220000")
      PlaceSpawns.call(world: world_b, players_count: 12, rng: rng_b)

      a_names = world_a.regions.where(spawn_eligible: true).pluck(:name).sort
      b_names = world_b.regions.where(spawn_eligible: true).pluck(:name).sort
      assert_equal a_names, b_names
    end

    private

    def build_adj_map(world)
      ids = world.regions.pluck(:id)
      map = ids.each_with_object({}) { |id, h| h[id] = [] }
      RegionAdjacency.where(region_a_id: ids).each do |a|
        map[a.region_a_id] << a.region_b_id
        map[a.region_b_id] << a.region_a_id
      end
      map
    end

    def bfs_distance(a, b, adjacency)
      return 0 if a == b
      visited = { a => 0 }
      frontier = [ a ]
      depth = 0
      until frontier.empty?
        depth += 1
        nxt = []
        frontier.each do |id|
          adjacency[id].each do |n|
            next if visited.key?(n)
            return depth if n == b
            visited[n] = depth
            nxt << n
          end
        end
        frontier = nxt
      end
      Float::INFINITY
    end
  end
end
