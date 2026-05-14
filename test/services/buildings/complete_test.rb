require "test_helper"

module Buildings
  class CompleteTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.update!(stockpiles: {
        "gold" => 100_000, "wood" => 100_000, "stone" => 100_000, "iron" => 100_000,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "bumps building level and sets completed_at" do
      order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      Complete.call(build_order: order)
      order.reload
      assert_equal 2, order.building.reload.level
      assert_not_nil order.completed_at
    end

    test "idempotent: calling twice does not double-bump" do
      order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      Complete.call(build_order: order)
      first_completed_at = order.reload.completed_at
      Complete.call(build_order: order)
      assert_equal first_completed_at, order.reload.completed_at
      assert_equal 2, order.building.reload.level
    end

    test "Stone Mason completion recalcs in-progress siblings' completes_at" do
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 10) # 2 slots
      stone_mason_order = Queue.call(kingdom: @kingdom, kind: "stone_mason", target_level: 1)
      quarry_order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      original_completes_at = quarry_order.completes_at

      Complete.call(build_order: stone_mason_order)
      new_completes_at = quarry_order.reload.completes_at
      assert new_completes_at < original_completes_at,
             "expected quarry to finish sooner after Stone Mason L1 (had #{original_completes_at}, now #{new_completes_at})"
    end

    test "non-Stone Mason completion does NOT recalc siblings" do
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 10) # 2 slots
      quarry_order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      barracks_order = Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
      original_quarry_completes_at = quarry_order.completes_at

      Complete.call(build_order: barracks_order)
      assert_equal original_quarry_completes_at.to_i, quarry_order.reload.completes_at.to_i
    end
  end
end
