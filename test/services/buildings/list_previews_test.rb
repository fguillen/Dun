require "test_helper"

module Buildings
  class ListPreviewsTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.update!(stockpiles: {
        "gold" => 50_000, "wood" => 50_000, "stone" => 50_000, "iron" => 50_000,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "returns one entry per Buildings::Catalog::KINDS, sorted by kind" do
      rows = ListPreviews.call(kingdom: @kingdom)
      assert_equal Catalog::KINDS.length, rows.length
      assert_equal Catalog::KINDS.sort, rows.map { |r| r[:kind] }
    end

    test "merges id, upgrade_possible, and build_order onto each entry" do
      rows = ListPreviews.call(kingdom: @kingdom)
      row = rows.find { |r| r[:kind] == "quarry" }
      assert_equal @kingdom.buildings.find_by(kind: "quarry").id, row[:id]
      assert_includes [ true, false ], row[:upgrade_possible]
      assert_nil row[:build_order]
    end

    test "delegates per-kind to UpgradePreview" do
      Catalog::KINDS.each do |kind|
        UpgradePreview.expects(:call).with(kingdom: @kingdom, kind: kind).returns(
          kind: kind, current_level: 1, target_level: 2, at_max_level: false,
          cost: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 },
          duration_seconds: 60, tier_gates_met: true, tier_gates_unmet: [],
          affordable: true, missing: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 }
        )
      end
      ListPreviews.call(kingdom: @kingdom)
    end

    test "upgrade_possible is true when cost/gates/level pass and no in-progress order" do
      rows = ListPreviews.call(kingdom: @kingdom)
      row = rows.find { |r| r[:kind] == "quarry" }
      assert_equal true, row[:upgrade_possible]
      assert_nil row[:build_order]
    end

    test "upgrade_possible is false when an in-progress order exists for the same building" do
      ::Buildings::Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      rows = ListPreviews.call(kingdom: @kingdom)
      row = rows.find { |r| r[:kind] == "quarry" }
      assert_not_nil row[:build_order]
      assert_equal false, row[:upgrade_possible]
    end

    test "upgrade_possible is false when at max level" do
      @kingdom.buildings.find_by(kind: "quarry").update!(level: Catalog::MAX_LEVEL)
      rows = ListPreviews.call(kingdom: @kingdom)
      row = rows.find { |r| r[:kind] == "quarry" }
      assert_equal true, row[:at_max_level]
      assert_equal false, row[:upgrade_possible]
    end

    test "upgrade_possible is false when tier gates are unmet" do
      rows = ListPreviews.call(kingdom: @kingdom)
      row = rows.find { |r| r[:kind] == "siege_workshop" }
      assert_equal false, row[:tier_gates_met]
      assert_equal false, row[:upgrade_possible]
    end

    test "upgrade_possible is false when unaffordable" do
      @kingdom.update!(stockpiles: {
        "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
        "checkpoint_at" => Time.current.iso8601
      })
      rows = ListPreviews.call(kingdom: @kingdom)
      row = rows.find { |r| r[:kind] == "quarry" }
      assert_equal false, row[:affordable]
      assert_equal false, row[:upgrade_possible]
    end
  end
end
