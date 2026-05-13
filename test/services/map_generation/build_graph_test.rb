require "test_helper"

module MapGeneration
  class BuildGraphTest < ActiveSupport::TestCase
    test "region count formula clamps per \u00a716.5 table" do
      [
        [ 4,  16 ], [ 8,  26 ], [ 12, 36 ], [ 16, 46 ], [ 20, 56 ], [ 24, 64 ], [ 30, 64 ]
      ].each do |players, expected|
        world = create(:world, seed: "deadbeef00000000")
        builder = BuildGraph.new(world: world, players_count: players, rng: Random.new(world.seed_int))
        assert_equal expected, builder.region_count, "expected #{expected} regions for #{players} players"
      end
    end

    test "produces the expected number of region rows" do
      world = create(:world, seed: "0000000000000001")
      BuildGraph.call(world: world, players_count: 8, rng: Random.new(world.seed_int))
      assert_equal 26, world.regions.count
    end

    test "every region is connected to at least one other (no isolated nodes)" do
      world = create(:world, seed: "0000000000000002")
      result = BuildGraph.call(world: world, players_count: 12, rng: Random.new(world.seed_int))

      counts = Hash.new(0)
      result.adjacencies.each do |a|
        counts[a.region_a_id] += 1
        counts[a.region_b_id] += 1
      end
      result.regions.each do |r|
        assert counts[r.id] >= 1, "region #{r.name} (#{r.id}) is isolated"
      end
    end

    test "average degree falls in [2.6, 3.6] window after pruning" do
      world = create(:world, seed: "0000000000000003")
      result = BuildGraph.call(world: world, players_count: 16, rng: Random.new(world.seed_int))

      n = result.regions.size
      avg = (2.0 * result.adjacencies.size) / n
      assert avg >= 2.6, "avg degree was #{avg}, expected >= 2.6"
      assert avg <= 3.6, "avg degree was #{avg}, expected <= 3.6"
    end

    test "same seed reproduces an identical map (positions, names, adjacencies)" do
      world_a = create(:world, seed: "abc1234567890def")
      world_b = create(:world, seed: "abc1234567890def")

      BuildGraph.call(world: world_a, players_count: 8, rng: Random.new(world_a.seed_int))
      BuildGraph.call(world: world_b, players_count: 8, rng: Random.new(world_b.seed_int))

      positions_a = world_a.regions.order(:name).map { |r| [ r.name, r.position["x"], r.position["y"] ] }
      positions_b = world_b.regions.order(:name).map { |r| [ r.name, r.position["x"], r.position["y"] ] }
      assert_equal positions_a, positions_b

      edges_a = RegionAdjacency.where(region_a_id: world_a.regions.select(:id)).pluck(:region_a_id, :region_b_id).sort
      edges_b = RegionAdjacency.where(region_a_id: world_b.regions.select(:id)).pluck(:region_a_id, :region_b_id).sort

      # IDs differ across worlds; compare structure via positions
      pos_a = world_a.regions.index_by(&:id)
      pos_b = world_b.regions.index_by(&:id)
      structural_a = edges_a.map { |x, y| [ pos_a[x].name, pos_a[y].name ].sort }.sort
      structural_b = edges_b.map { |x, y| [ pos_b[x].name, pos_b[y].name ].sort }.sort
      assert_equal structural_a, structural_b
    end

    test "marks hub regions when degree >= 5" do
      world = create(:world, seed: "0000000000000005")
      result = BuildGraph.call(world: world, players_count: 8, rng: Random.new(world.seed_int))

      counts = Hash.new(0)
      result.adjacencies.each { |a| counts[a.region_a_id] += 1; counts[a.region_b_id] += 1 }

      result.regions.each do |r|
        if counts[r.id] >= 5
          assert r.is_hub, "expected #{r.name} (degree #{counts[r.id]}) to be a hub"
        else
          refute r.is_hub, "expected #{r.name} (degree #{counts[r.id]}) NOT to be a hub"
        end
      end
    end
  end
end
