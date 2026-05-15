require "test_helper"

module Training
  class CancelTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 1)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      @kingdom.update!(stockpiles: {
        "gold" => 50_000, "wood" => 50_000, "stone" => 50_000, "iron" => 50_000,
        "checkpoint_at" => Time.current.iso8601
      })
      @order = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 4)
      @gold_after_queue = @kingdom.reload.stockpiles["gold"]
    end

    test "refunds 75% of cost × count (floored)" do
      cost = Units::Catalog.cost_for("levy")
      Cancel.call(training_order: @order)
      @kingdom.reload
      expected_refund = (cost["gold"] * 4 * Cancel::REFUND_RATIO).floor
      assert_equal @gold_after_queue + expected_refund, @kingdom.stockpiles["gold"]
    end

    test "sets cancelled_at" do
      Cancel.call(training_order: @order)
      assert_not_nil @order.reload.cancelled_at
    end

    test "rejects already-resolved order" do
      Cancel.call(training_order: @order)
      assert_raises(Cancel::AlreadyResolved) { Cancel.call(training_order: @order) }
    end

    test "rejects already-completed order" do
      @order.update!(completed_at: Time.current)
      assert_raises(Cancel::AlreadyResolved) { Cancel.call(training_order: @order) }
    end

    test "marks the matching ScheduledEvent processed" do
      event = ScheduledEvent.pending
        .where(kind: "training_completion")
        .where("payload->>'training_order_id' = ?", @order.id)
        .first
      assert event

      Cancel.call(training_order: @order)
      assert event.reload.processed_at.present?
    end

    test "emits dun.training_order.cancelled" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.training_order.cancelled") do
        Cancel.call(training_order: @order)
      end

      assert_equal 1, events.size
      assert_equal @order.id, events.first[:training_order_id]
    end
  end
end
