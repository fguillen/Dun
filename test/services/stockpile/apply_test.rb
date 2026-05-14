require "test_helper"

module Stockpile
  class ApplyTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.update!(stockpiles: {
        "gold" => 1_000, "wood" => 1_000, "stone" => 1_000, "iron" => 1_000,
        "checkpoint_at" => 10.minutes.ago.iso8601
      })
    end

    test "deducts within balance and updates checkpoint" do
      old_checkpoint = @kingdom.stockpiles["checkpoint_at"]
      Apply.call(kingdom: @kingdom, deltas: { "gold" => -300, "wood" => -200 })
      @kingdom.reload
      # 10 min accrual: gold_mint L1 = 30/h * (10/60) = 5. Wood lumber_camp L1 = 40/h * (10/60) = 6 (floored).
      assert_in_delta 1_000 + 5 - 300, @kingdom.stockpiles["gold"], 1
      assert_in_delta 1_000 + 6 - 200, @kingdom.stockpiles["wood"], 1
      assert_not_equal old_checkpoint, @kingdom.stockpiles["checkpoint_at"]
    end

    test "raises InsufficientResources when delta would go negative" do
      assert_raises(Apply::InsufficientResources) do
        Apply.call(kingdom: @kingdom, deltas: { "gold" => -2_000 })
      end
      @kingdom.reload
      assert_equal 1_000, @kingdom.stockpiles["gold"]
    end

    test "clamps credits to warehouse cap" do
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 0) # cap 5000
      Apply.call(kingdom: @kingdom, deltas: { "gold" => 999_999 })
      @kingdom.reload
      assert_equal Buildings::Catalog.warehouse_cap(0), @kingdom.stockpiles["gold"]
    end

    test "applies against materialized (accrued) value, not stored" do
      @kingdom.buildings.find_by(kind: "gold_mint").update!(level: 4) # 120/h
      @kingdom.update!(stockpiles: {
        "gold" => 1_000, "wood" => 1_000, "stone" => 1_000, "iron" => 1_000,
        "checkpoint_at" => 2.hours.ago.iso8601
      })
      Apply.call(kingdom: @kingdom, deltas: { "gold" => -1_100 })
      @kingdom.reload
      # Started 1000 accrued 240 over 2h = 1240. After -1100 = 140.
      assert_equal 140, @kingdom.stockpiles["gold"]
    end
  end
end
