require "test_helper"

module Buildings
  class CancelTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.update!(stockpiles: {
        "gold" => 50_000, "wood" => 50_000, "stone" => 50_000, "iron" => 50_000,
        "checkpoint_at" => Time.current.iso8601
      })
      @order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      @gold_after_queue = @kingdom.reload.stockpiles["gold"]
    end

    test "refunds 75% of cost (floored)" do
      cost = CostFor.call(kind: "quarry", level: 2)
      Cancel.call(build_order: @order)
      @kingdom.reload
      assert_equal @gold_after_queue + (cost["gold"] * 0.75).floor, @kingdom.stockpiles["gold"]
    end

    test "sets cancelled_at" do
      Cancel.call(build_order: @order)
      assert_not_nil @order.reload.cancelled_at
    end

    test "frees the build slot" do
      Cancel.call(build_order: @order)
      new_order = Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
      assert_kind_of BuildOrder, new_order
      assert_equal "barracks", new_order.building.kind
    end

    test "rejects already-resolved order" do
      Cancel.call(build_order: @order)
      assert_raises(Cancel::AlreadyResolved) { Cancel.call(build_order: @order) }
    end

    test "rejects already-completed order" do
      @order.update!(completed_at: Time.current)
      assert_raises(Cancel::AlreadyResolved) { Cancel.call(build_order: @order) }
    end
  end
end
