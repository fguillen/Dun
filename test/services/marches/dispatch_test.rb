require "test_helper"

module Marches
  class DispatchTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace)
      @home = create(:region, world: @world, terrain: "plains", name: "Home")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@home, @target)

      kingdom = create(:kingdom, world: @world, home_region: @home)
      @army = create(:army, kingdom: kingdom, location_region: @home, name: "Vanguard",
        composition: { "knight" => 5 })
    end

    test "creates MarchOrder with computed arrives_at and sets army marching" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "reinforce")

      assert_equal "reinforce", order.intent
      assert_equal [ @home.id, @target.id ], order.path
      assert_in_delta order.dispatched_at + 3600, order.arrives_at, 1.0
      assert_equal "marching", @army.reload.status
    end

    test "schedules a march_arrival ScheduledEvent at arrives_at" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", order.id)
        .first
      assert event
      assert_in_delta order.arrives_at, event.fire_at, 1
    end

    test "rejects when army is already marching" do
      @army.update!(status: "marching")
      assert_raises(Dispatch::NotHome) do
        Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      end
    end

    test "rejects unknown intent" do
      assert_raises(Dispatch::InvalidIntent) do
        Dispatch.call(army: @army, target_region: @target, intent: "siege")
      end
    end

    test "rejects when world is not grace/active" do
      @world.update!(status: "archived", archived_at: 1.hour.ago)
      assert_raises(Dispatch::WorldNotActive) do
        Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      end
    end

    test "emits dun.march_order.dispatched" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.march_order.dispatched") do
        Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      end

      assert_equal 1, events.size
      assert_equal "reinforce", events.first[:intent]
      assert_equal @target.id, events.first[:target_region_id]
    end
  end
end
