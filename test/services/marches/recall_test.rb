require "test_helper"

module Marches
  class RecallTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace)
      @home = create(:region, world: @world, terrain: "plains", name: "Home")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@home, @target)

      kingdom = create(:kingdom, world: @world, home_region: @home)
      @army = create(:army, kingdom: kingdom, location_region: @home, name: "Vanguard",
        composition: { "knight" => 5 })
      @order = Dispatch.call(army: @army, target_region: @target, intent: "attack")
    end

    test "cancels the pending march_arrival event" do
      pending_event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", @order.id)
        .first
      assert pending_event

      Recall.call(march_order: @order)
      assert pending_event.reload.processed_at.present?
    end

    test "marks the original march recalled_at" do
      Recall.call(march_order: @order)
      assert_not_nil @order.reload.recalled_at
    end

    test "creates a return MarchOrder with reversed path and reinforce intent" do
      return_order = Recall.call(march_order: @order)
      assert_equal "reinforce", return_order.intent
      assert_equal @target.id, return_order.origin_region_id
      assert_equal @home.id, return_order.target_region_id
      assert_equal @order.path.reverse, return_order.path
    end

    test "return time equals elapsed-since-dispatch (v1 retrace simplification)" do
      travel(2.minutes) do
        return_order = Recall.call(march_order: @order)
        elapsed = Time.current - @order.dispatched_at
        assert_in_delta Time.current + elapsed, return_order.arrives_at, 1.0
      end
    end

    test "sets army status to returning (no unit losses)" do
      original_composition = @army.composition.dup
      Recall.call(march_order: @order)
      assert_equal "returning", @army.reload.status
      assert_equal original_composition, @army.composition
    end

    test "rejects already-resolved orders" do
      Recall.call(march_order: @order)
      assert_raises(Recall::AlreadyResolved) do
        Recall.call(march_order: @order)
      end
    end

    test "emits dun.march_order.recalled" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.march_order.recalled") do
        Recall.call(march_order: @order)
      end

      assert_equal 1, events.size
      assert_equal @order.id, events.first[:march_order_id]
      assert events.first[:return_march_order_id].present?
    end
  end
end
