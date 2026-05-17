require "test_helper"

module Training
  class PreviewTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 3)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      stock(50_000)
    end

    def stock(amount)
      @kingdom.update!(stockpiles: {
        "gold" => amount, "wood" => amount, "stone" => amount, "iron" => amount,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "happy path: levy at barracks, count 10" do
      result = Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 10)

      per_unit = Units::Catalog.cost_for("levy")
      assert_equal per_unit, result[:per_unit_cost]
      assert_equal per_unit.transform_values { |v| v * 10 }, result[:total_cost]
      assert_equal "barracks", result[:building_kind]
      assert_equal "levy", result[:unit]
      assert_equal 10, result[:count]
      assert_equal 3, result[:building_level]
      assert_equal true, result[:building_built]
      assert_equal true, result[:unit_trainable_here]
    end

    test "total_seconds = per_unit_seconds * count and reflects building level" do
      result = Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 4)
      per_unit_expected = Units::TrainingTimeFor.call(unit: "levy", building_level: 3).to_i
      assert_equal per_unit_expected, result[:per_unit_seconds]
      assert_equal per_unit_expected * 4, result[:total_seconds]

      @kingdom.buildings.find_by(kind: "barracks").update!(level: 10)
      faster = Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 4)
      assert faster[:per_unit_seconds] < result[:per_unit_seconds]
    end

    test "affordability flips on shortfall" do
      stock(100)
      result = Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "pikeman", count: 5)
      assert_equal false, result[:affordable]
      assert result[:missing]["iron"] > 0
    end

    test "max_affordable_count is min of stockpile/per_unit_cost across resources" do
      @kingdom.update!(stockpiles: {
        "gold" => 200, "wood" => 1000, "stone" => 1000, "iron" => 1000,
        "checkpoint_at" => Time.current.iso8601
      })
      per_unit = Units::Catalog.cost_for("levy")
      expected = [ 200 / per_unit["gold"], 1000 / per_unit["wood"], 1000 / per_unit["iron"] ].min
      result = Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      assert_equal expected, result[:max_affordable_count]
    end

    test "unit_trainable_here is false when unit/building mismatch" do
      @kingdom.buildings.find_by(kind: "stable").update!(level: 1)
      result = Preview.call(kingdom: @kingdom, building_kind: "stable", unit: "levy", count: 1)
      assert_equal false, result[:unit_trainable_here]
      assert_equal Units::Catalog.cost_for("levy"), result[:per_unit_cost]
    end

    test "building_built is false when level is 0" do
      @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 0)
      result = Preview.call(kingdom: @kingdom, building_kind: "siege_workshop", unit: "catapult", count: 1)
      assert_equal 0, result[:building_level]
      assert_equal false, result[:building_built]
    end

    test "unknown unit raises" do
      assert_raises(Preview::UnknownUnit) do
        Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "ninja", count: 1)
      end
    end

    test "invalid building_kind raises" do
      assert_raises(Preview::InvalidBuildingKind) do
        Preview.call(kingdom: @kingdom, building_kind: "warehouse", unit: "levy", count: 1)
      end
    end

    test "count must be positive" do
      assert_raises(Preview::InvalidCount) do
        Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 0)
      end
    end
  end
end
