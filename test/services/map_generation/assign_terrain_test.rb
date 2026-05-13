require "test_helper"

module MapGeneration
  class AssignTerrainTest < ActiveSupport::TestCase
    def build_world(seed: "abcdef0123456789", players: 16)
      world = create(:world, seed: seed)
      rng = Random.new(world.seed_int)
      BuildGraph.call(world: world, players_count: players, rng: rng)
      world
    end

    test "assigns one of the five terrain types to every region" do
      world = build_world
      AssignTerrain.call(world: world, rng: Random.new(world.seed_int))
      world.reload
      world.regions.each do |r|
        assert_includes Region::TERRAINS, r.terrain
      end
    end

    test "share of each terrain is within \u00b110pp of the target" do
      world = build_world(seed: "0000000000000000", players: 24)
      AssignTerrain.call(world: world, rng: Random.new(world.seed_int))
      world.reload
      total = world.regions.count.to_f

      AssignTerrain::TARGET_SHARES.each do |terrain, target|
        actual = world.regions.where(terrain: terrain).count / total
        assert (actual - target).abs <= 0.10, "#{terrain}: target #{target}, actual #{actual.round(3)} (off by #{(actual - target).abs.round(3)})"
      end
    end

    test "same seed reproduces identical terrain assignment" do
      world_a = create(:world, seed: "feedface00000000")
      world_b = create(:world, seed: "feedface00000000")
      rng_a = Random.new(world_a.seed_int)
      rng_b = Random.new(world_b.seed_int)
      BuildGraph.call(world: world_a, players_count: 12, rng: rng_a)
      AssignTerrain.call(world: world_a, rng: rng_a)
      BuildGraph.call(world: world_b, players_count: 12, rng: rng_b)
      AssignTerrain.call(world: world_b, rng: rng_b)

      terrains_a = world_a.regions.order(:name).pluck(:terrain)
      terrains_b = world_b.regions.order(:name).pluck(:terrain)
      assert_equal terrains_a, terrains_b
    end
  end
end
