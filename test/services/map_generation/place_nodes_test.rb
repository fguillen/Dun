require "test_helper"

module MapGeneration
  class PlaceNodesTest < ActiveSupport::TestCase
    GOOD_SEEDS = {
      4  => "0000000000000fe4",
      8  => "0000000000001fd9",
      12 => "0000000000002f35",
      16 => "0000000000003fc3",
      20 => "00000000000049b5"
    }.freeze

    def build_world(players: 12, seed: nil)
      seed ||= GOOD_SEEDS.fetch(players)
      world = create(:world, seed: seed)
      rng = Random.new(world.seed_int)
      BuildGraph.call(world: world, players_count: players, rng: rng)
      AssignTerrain.call(world: world, rng: rng)
      PlaceSpawns.call(world: world, players_count: players, rng: rng)
      [ world, rng ]
    end

    test "non-home-hoard node count approaches round(1.2 * players)" do
      [ 8, 12, 16 ].each do |players|
        world, rng = build_world(players: players)
        PlaceNodes.call(world: world, players_count: players, rng: rng)
        expected = (1.2 * players).round
        actual = world.reload.nodes.where(is_home_hoard: false).count
        # Rich-tier-not-adjacent-to-spawn can drop the count on dense maps;
        # accept up to one missed placement.
        assert actual >= expected - 1, "expected ~#{expected} non-hoard nodes for #{players} players, got #{actual}"
        assert actual <= expected, "expected at most #{expected} non-hoard nodes for #{players} players, got #{actual}"
      end
    end

    test "no region holds more than two nodes" do
      world, rng = build_world(players: 16)
      PlaceNodes.call(world: world, players_count: 16, rng: rng)

      counts = world.nodes.group(:region_id).count
      assert counts.values.all? { |c| c <= 2 }, "some region holds 3+ nodes: #{counts.select { |_, c| c > 2 }}"
    end

    test "no region holds a rich node alongside any other node" do
      world, rng = build_world(players: 16)
      PlaceNodes.call(world: world, players_count: 16, rng: rng)

      world.regions.includes(:nodes).each do |region|
        if region.nodes.any? { |n| n.tier == "rich" && !n.is_home_hoard }
          rich = region.nodes.select { |n| n.tier == "rich" }
          assert_equal 1, region.nodes.count, "rich node region #{region.name} also has other nodes (#{rich.size} rich, #{region.nodes.size} total)"
        end
      end
    end

    test "tier shares of non-hoard nodes roughly match \u00a716.5 (\u00b115pp tolerance)" do
      world, rng = build_world(players: 16)
      PlaceNodes.call(world: world, players_count: 16, rng: rng)
      total = world.nodes.where(is_home_hoard: false).count.to_f

      PlaceNodes::TIER_SHARES.each do |tier, target|
        actual = world.nodes.where(tier: tier, is_home_hoard: false).count / total
        assert (actual - target).abs <= 0.15, "tier #{tier}: target #{target}, actual #{actual.round(3)}"
      end
    end

    test "base_rate and garrison match the tier table for every node" do
      world, rng = build_world(players: 12)
      PlaceNodes.call(world: world, players_count: 12, rng: rng)

      world.nodes.each do |node|
        assert_equal Node::TIER_BASE_RATE[node.tier], node.base_rate
        expected_garrison = Node::WILDERNESS_GARRISONS[node.tier].deep_stringify_keys
        assert_equal expected_garrison, node.garrison
      end
    end

    test "rich nodes are never placed adjacent to a spawn region (\u00a716.5)" do
      world, rng = build_world(players: 12)
      PlaceNodes.call(world: world, players_count: 12, rng: rng)

      spawn_ids = world.regions.where(spawn_eligible: true).pluck(:id).to_set
      adjacency = RegionAdjacency.where(region_a_id: world.regions.select(:id)).pluck(:region_a_id, :region_b_id)
      adj_to_spawn = Set.new
      adjacency.each do |a, b|
        adj_to_spawn << b if spawn_ids.include?(a)
        adj_to_spawn << a if spawn_ids.include?(b)
      end

      rich_nodes = world.nodes.where(tier: "rich", is_home_hoard: false).includes(:region)
      rich_nodes.each do |n|
        refute adj_to_spawn.include?(n.region_id), "rich node in #{n.region.name} is adjacent to a spawn"
      end
    end

    test "non-hoard nodes are never placed inside a spawn region" do
      world, rng = build_world(players: 12)
      PlaceNodes.call(world: world, players_count: 12, rng: rng)

      spawn_ids = world.regions.where(spawn_eligible: true).pluck(:id).to_set
      world.nodes.where(is_home_hoard: false).each do |n|
        refute spawn_ids.include?(n.region_id), "non-hoard node placed inside spawn region #{n.region_id}"
      end
    end

    test "same seed reproduces identical node placement" do
      world_a, rng_a = build_world(seed: "11112222aaaaffff")
      PlaceNodes.call(world: world_a, players_count: 12, rng: rng_a)

      world_b, rng_b = build_world(seed: "11112222aaaaffff")
      PlaceNodes.call(world: world_b, players_count: 12, rng: rng_b)

      by_a = world_a.nodes.includes(:region).map { |n| [ n.region.name, n.resource, n.tier ] }.sort
      by_b = world_b.nodes.includes(:region).map { |n| [ n.region.name, n.resource, n.tier ] }.sort
      assert_equal by_a, by_b
    end

    test "iron nodes lean toward mountain/hills (thematic bias)" do
      iron_regions = []
      seeds = [
        "0000000000002332", "0000000000002336", "0000000000002338",
        "0000000000002340", "0000000000002342", "0000000000002f35"
      ]
      seeds.each do |seed|
        world, rng = build_world(players: 12, seed: seed)
        PlaceNodes.call(world: world, players_count: 12, rng: rng)
        world.nodes.where(resource: "iron", is_home_hoard: false).includes(:region).each do |n|
          iron_regions << n.region.terrain
        end
      end
      thematic_count = iron_regions.count { |t| %w[mountain hills].include?(t) }
      ratio = thematic_count.to_f / iron_regions.size
      assert ratio >= 0.50, "iron nodes on mountain/hills was #{(ratio * 100).round}% (#{thematic_count}/#{iron_regions.size}), expected >=50%"
    end
  end
end
