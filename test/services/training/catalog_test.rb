require "test_helper"

module Training
  class CatalogTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 3)
      @kingdom.buildings.find_by(kind: "stable").update!(level: 2)
      @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 0)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      stock(50_000)
    end

    def stock(amount)
      @kingdom.update!(stockpiles: {
        "gold" => amount, "wood" => amount, "stone" => amount, "iron" => amount,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "building omitted returns all three military buildings in order" do
      result = Catalog.call(kingdom: @kingdom)
      kinds = result[:buildings].map { |b| b[:building_kind] }
      assert_equal %w[barracks stable siege_workshop], kinds
    end

    test "building filter returns only that building" do
      result = Catalog.call(kingdom: @kingdom, building_kind: "stable")
      assert_equal 1, result[:buildings].length
      building = result[:buildings].first
      assert_equal "stable", building[:building_kind]
      assert_equal %w[knight scout royal_guard], building[:units].map { |u| u[:unit] }
    end

    test "each building lists exactly its Units::Catalog::TRAINS_AT units" do
      result = Catalog.call(kingdom: @kingdom)
      Units::Catalog::TRAINS_AT.each do |kind, units|
        building = result[:buildings].find { |b| b[:building_kind] == kind }
        assert_equal units, building[:units].map { |u| u[:unit] }
      end
    end

    test "unit entry equals Training::Preview at count 1" do
      catalog_unit = Catalog.call(kingdom: @kingdom, building_kind: "barracks")
        .dig(:buildings, 0, :units)
        .find { |u| u[:unit] == "levy" }
      preview = Preview.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)

      assert_equal preview[:per_unit_cost], catalog_unit[:per_unit_cost]
      assert_equal preview[:per_unit_seconds], catalog_unit[:per_unit_seconds]
      assert_equal preview[:max_affordable_count], catalog_unit[:max_affordable_count]
      assert_equal preview[:building_built] && preview[:unit_trainable_here], catalog_unit[:trainable]
    end

    test "kingdom_id is a string" do
      result = Catalog.call(kingdom: @kingdom)
      assert_equal @kingdom.id.to_s, result[:kingdom_id]
    end

    test "built building reports building_built true and trainable units" do
      building = Catalog.call(kingdom: @kingdom, building_kind: "barracks")[:buildings].first
      assert_equal true, building[:building_built]
      assert_equal 3, building[:building_level]
      assert building[:units].all? { |u| u[:trainable] }
    end

    test "unbuilt building reports building_built false, level 0, units not trainable" do
      building = Catalog.call(kingdom: @kingdom, building_kind: "siege_workshop")[:buildings].first
      assert_equal false, building[:building_built]
      assert_equal 0, building[:building_level]
      assert building[:units].none? { |u| u[:trainable] }
      assert building[:units].all? { |u| u[:per_unit_seconds] > 0 }
    end

    test "per_unit_seconds shrinks as building level rises" do
      slow = Catalog.call(kingdom: @kingdom, building_kind: "barracks")
        .dig(:buildings, 0, :units).find { |u| u[:unit] == "levy" }[:per_unit_seconds]
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 10)
      fast = Catalog.call(kingdom: @kingdom, building_kind: "barracks")
        .dig(:buildings, 0, :units).find { |u| u[:unit] == "levy" }[:per_unit_seconds]
      assert fast < slow
    end

    test "max_affordable_count is the stockpile-bound count for the unit" do
      @kingdom.update!(stockpiles: {
        "gold" => 200, "wood" => 1000, "stone" => 1000, "iron" => 1000,
        "checkpoint_at" => Time.current.iso8601
      })
      per_unit = Units::Catalog.cost_for("levy")
      expected = [ 200 / per_unit["gold"], 1000 / per_unit["wood"], 1000 / per_unit["iron"] ].min
      levy = Catalog.call(kingdom: @kingdom, building_kind: "barracks")
        .dig(:buildings, 0, :units).find { |u| u[:unit] == "levy" }
      assert_equal expected, levy[:max_affordable_count]
    end

    test "max_affordable_count is 0 when stockpile is empty" do
      stock(0)
      levy = Catalog.call(kingdom: @kingdom, building_kind: "barracks")
        .dig(:buildings, 0, :units).find { |u| u[:unit] == "levy" }
      assert_equal 0, levy[:max_affordable_count]
    end

    test "invalid building kind raises InvalidBuildingKind" do
      assert_raises(Catalog::InvalidBuildingKind) do
        Catalog.call(kingdom: @kingdom, building_kind: "warehouse")
      end
    end

    test "nil and blank building_kind both return all three buildings" do
      assert_equal 3, Catalog.call(kingdom: @kingdom, building_kind: nil)[:buildings].length
      assert_equal 3, Catalog.call(kingdom: @kingdom, building_kind: "")[:buildings].length
    end
  end
end
