require "test_helper"

module MapGeneration
  class GenerateTest < ActiveSupport::TestCase
    test "end-to-end map generation populates regions, terrain, spawns, and nodes" do
      world = create(:world, seed: "0000000000002f35")
      Generate.call(world: world, players_count: 12)

      world.reload
      assert_equal 36, world.regions.count

      world.regions.each do |r|
        assert_includes Region::TERRAINS, r.terrain
      end

      spawns = world.regions.where(spawn_eligible: true)
      assert spawns.count >= 12, "expected at least 12 spawns, got #{spawns.count}"

      home_hoards = world.nodes.where(is_home_hoard: true)
      assert_equal spawns.count, home_hoards.count

      total_non_hoard = world.nodes.where(is_home_hoard: false).count
      assert total_non_hoard >= (1.2 * 12).round - 1
      assert total_non_hoard <= (1.2 * 12).round
    end

    test "same seed reproduces the entire map" do
      a = create(:world, seed: "0000000000002338")
      b = create(:world, seed: "0000000000002338")

      Generate.call(world: a, players_count: 12)
      Generate.call(world: b, players_count: 12)

      a_signature = a.reload.regions.order(:id).map { |r| [ r.name, r.terrain, r.spawn_eligible, r.position ] }
      b_signature = b.reload.regions.order(:id).map { |r| [ r.name, r.terrain, r.spawn_eligible, r.position ] }
      assert_equal a_signature, b_signature
    end
  end
end
