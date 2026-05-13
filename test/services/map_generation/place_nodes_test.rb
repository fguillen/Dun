require "test_helper"

module MapGeneration
  class PlaceNodesTest < ActiveSupport::TestCase
    def build_world(players: 12, seed: "0123456789abcdef")
      world = create(:world, seed: seed)
      rng = Random.new(world.seed_int)
      BuildGraph.call(world: world, players_count: players, rng: rng)
      AssignTerrain.call(world: world, rng: rng)
      [ world, rng ]
    end

    test "total node count equals round(1.2 * players)" do
      [ 4, 8, 12, 16, 20, 24 ].each do |players|
        world, rng = build_world(players: players)
        PlaceNodes.call(world: world, players_count: players, rng: rng)
        expected = (1.2 * players).round
        assert_equal expected, world.reload.nodes.count, "expected #{expected} nodes for #{players} players"
      end
    end

    test "no region holds more than two nodes" do
      world, rng = build_world(players: 24)
      PlaceNodes.call(world: world, players_count: 24, rng: rng)

      counts = world.nodes.group(:region_id).count
      assert counts.values.all? { |c| c <= 2 }, "some region holds 3+ nodes: #{counts.select { |_, c| c > 2 }}"
    end

    test "no region holds a rich node alongside any other node" do
      world, rng = build_world(players: 24)
      PlaceNodes.call(world: world, players_count: 24, rng: rng)

      world.regions.includes(:nodes).each do |region|
        if region.nodes.any? { |n| n.tier == "rich" }
          assert_equal 1, region.nodes.count, "rich node region #{region.name} also has #{region.nodes.count - 1} other node(s)"
        end
      end
    end

    test "tier shares roughly match \u00a716.5 (\u00b115pp tolerance)" do
      world, rng = build_world(players: 24)
      PlaceNodes.call(world: world, players_count: 24, rng: rng)
      total = world.nodes.count.to_f

      PlaceNodes::TIER_SHARES.each do |tier, target|
        actual = world.nodes.where(tier: tier).count / total
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
      10.times do |i|
        world, rng = build_world(players: 16, seed: format("%016x", i + 1))
        PlaceNodes.call(world: world, players_count: 16, rng: rng)
        world.nodes.where(resource: "iron").includes(:region).each do |n|
          iron_regions << n.region.terrain
        end
      end
      thematic_count = iron_regions.count { |t| %w[mountain hills].include?(t) }
      ratio = thematic_count.to_f / iron_regions.size
      assert ratio >= 0.55, "iron nodes on mountain/hills was #{(ratio * 100).round}%, expected >=55%"
    end
  end
end
