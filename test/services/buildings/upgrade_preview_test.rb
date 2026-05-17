require "test_helper"

module Buildings
  class UpgradePreviewTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      stock(50_000)
    end

    def stock(amount)
      @kingdom.update!(stockpiles: {
        "gold" => amount, "wood" => amount, "stone" => amount, "iron" => amount,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "next-level cost for an existing building matches CostFor" do
      result = UpgradePreview.call(kingdom: @kingdom, kind: "quarry")
      assert_equal 1, result[:current_level]
      assert_equal 2, result[:target_level]
      assert_equal false, result[:at_max_level]
      assert_equal CostFor.call(kind: "quarry", level: 2), result[:cost]
    end

    test "absent building previews level 1 from level 0" do
      result = UpgradePreview.call(kingdom: @kingdom, kind: "town_hall")
      assert_equal 0, result[:current_level]
      assert_equal 1, result[:target_level]
      assert_equal CostFor.call(kind: "town_hall", level: 1), result[:cost]
    end

    test "at max level returns nil cost and target_level" do
      @kingdom.buildings.find_by(kind: "quarry").update!(level: Catalog::MAX_LEVEL)
      result = UpgradePreview.call(kingdom: @kingdom, kind: "quarry")
      assert_equal Catalog::MAX_LEVEL, result[:current_level]
      assert_nil result[:target_level]
      assert_equal true, result[:at_max_level]
      assert_nil result[:cost]
      assert_nil result[:duration_seconds]
      assert_equal false, result[:affordable]
    end

    test "affordability is true when stockpile covers cost" do
      result = UpgradePreview.call(kingdom: @kingdom, kind: "quarry")
      assert_equal true, result[:affordable]
      assert_equal({ "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 }, result[:missing])
    end

    test "affordability is false when stockpile is short" do
      stock(10)
      result = UpgradePreview.call(kingdom: @kingdom, kind: "quarry")
      assert_equal false, result[:affordable]
      cost = CostFor.call(kind: "quarry", level: 2)
      assert_equal cost["gold"] - 10, result[:missing]["gold"]
    end

    test "tier gate unmet for siege_workshop when barracks/iron_mine are low" do
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 3)
      @kingdom.buildings.find_by(kind: "iron_mine").update!(level: 4)
      result = UpgradePreview.call(kingdom: @kingdom, kind: "siege_workshop")
      assert_equal false, result[:tier_gates_met]
      kinds = result[:tier_gates_unmet].map { |g| g[:kind] }
      assert_includes kinds, "barracks"
      assert_includes kinds, "iron_mine"
    end

    test "tier gate met when prerequisites are satisfied" do
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 5)
      @kingdom.buildings.find_by(kind: "iron_mine").update!(level: 5)
      result = UpgradePreview.call(kingdom: @kingdom, kind: "siege_workshop")
      assert_equal true, result[:tier_gates_met]
      assert_equal [], result[:tier_gates_unmet]
    end

    test "duration reflects stone mason discount" do
      base = UpgradePreview.call(kingdom: @kingdom, kind: "quarry")[:duration_seconds]
      @kingdom.buildings.find_by(kind: "stone_mason").update!(level: 5)
      discounted = UpgradePreview.call(kingdom: @kingdom, kind: "quarry")[:duration_seconds]
      assert discounted < base, "expected stone mason to reduce duration"
    end

    test "unknown building kind raises" do
      assert_raises(UpgradePreview::UnknownBuilding) do
        UpgradePreview.call(kingdom: @kingdom, kind: "castle")
      end
    end
  end
end
