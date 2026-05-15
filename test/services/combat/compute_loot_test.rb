require "test_helper"

module Combat
  class ComputeLootTest < ActiveSupport::TestCase
    setup do
      world = create(:world, :active)
      @defender = create(:kingdom, :with_buildings, world: world)
    end

    test "25% per-resource cap dominates when attacker capacity is huge" do
      @defender.update!(stockpiles: {
        "gold" => 10_000, "wood" => 10_000, "stone" => 10_000, "iron" => 10_000,
        "checkpoint_at" => Time.current.iso8601
      })
      # 10 catapults => 10 × 200 capacity = 2000 / 4 = 500 per resource share
      loot = ComputeLoot.call(defender_kingdom: @defender, attacker_composition: { "catapult" => 10 })
      assert_equal({ "gold" => 500, "wood" => 500, "stone" => 500, "iron" => 500 }, loot)
    end

    test "capacity share dominates when attacker is small" do
      @defender.update!(stockpiles: {
        "gold" => 10_000, "wood" => 10_000, "stone" => 10_000, "iron" => 10_000,
        "checkpoint_at" => Time.current.iso8601
      })
      # 1 scout => 10 capacity / 4 = 2 per resource share. 25% × 10k = 2500. Min = 2.
      loot = ComputeLoot.call(defender_kingdom: @defender, attacker_composition: { "scout" => 1 })
      assert_equal({ "gold" => 2, "wood" => 2, "stone" => 2, "iron" => 2 }, loot)
    end

    test "lower of the two caps always wins per resource" do
      @defender.update!(stockpiles: {
        "gold" => 100, "wood" => 100_000, "stone" => 0, "iron" => 4_000,
        "checkpoint_at" => Time.current.iso8601
      })
      # 5 knights → 5 × 80 = 400 capacity → 100 per resource share
      loot = ComputeLoot.call(defender_kingdom: @defender, attacker_composition: { "knight" => 5 })
      assert_equal(25, loot["gold"])         # 25% of 100
      assert_equal(100, loot["wood"])        # capacity share wins (vs 25k)
      assert_equal(0, loot["stone"])         # nothing to take
      assert_equal(100, loot["iron"])        # capacity share wins (vs 1000)
    end

    test "zero composition produces zero loot" do
      @defender.update!(stockpiles: {
        "gold" => 10_000, "wood" => 10_000, "stone" => 10_000, "iron" => 10_000,
        "checkpoint_at" => Time.current.iso8601
      })
      loot = ComputeLoot.call(defender_kingdom: @defender, attacker_composition: {})
      assert_equal({ "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 }, loot)
    end
  end
end
