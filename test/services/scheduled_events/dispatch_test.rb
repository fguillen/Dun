require "test_helper"

module ScheduledEvents
  class DispatchTest < ActiveSupport::TestCase
    test "build_completion handler completes the build order and marks the event processed" do
      kingdom = create(:kingdom, :with_buildings)
      building = kingdom.buildings.find_by(kind: "quarry")
      order = create(:build_order, kingdom: kingdom, building: building, target_level: 2, completes_at: 1.minute.ago)
      event = create(:scheduled_event,
        world: kingdom.world,
        kind: "build_completion",
        fire_at: 1.minute.ago,
        payload: { "build_order_id" => order.id })

      Dispatch.call(event)

      assert event.reload.processed_at.present?
      assert order.reload.completed_at.present?
      assert_equal 2, building.reload.level
    end

    test "build_completion is a no-op when the build order has been deleted" do
      world = create(:world, :active)
      event = create(:scheduled_event,
        world: world,
        kind: "build_completion",
        fire_at: 1.minute.ago,
        payload: { "build_order_id" => "01HZZZZZZZZZZZZZZZZZZZZZZZ" })

      assert_nothing_raised { Dispatch.call(event) }
      assert event.reload.processed_at.present?
    end

    test "grace_expiry handler transitions world to active" do
      world = create(:world, :grace)
      event = create(:scheduled_event,
        world: world,
        kind: "grace_expiry",
        fire_at: 1.minute.ago)

      Dispatch.call(event)

      assert_equal "active", world.reload.status
      assert event.reload.processed_at.present?
    end

    test "no-op on already-processed event" do
      event = create(:scheduled_event, processed_at: 1.minute.ago)
      Dispatch.call(event)
      assert_in_delta 1.minute.ago, event.reload.processed_at, 5
    end

    test "unknown kind raises and leaves event pending" do
      world = create(:world, :active)
      event = ScheduledEvent.create!(
        world: world,
        kind: "weather_edge",
        fire_at: 1.minute.ago
      )

      assert_raises(Dispatch::UnknownKind) { Dispatch.call(event) }
      assert event.reload.pending?
    end

    test "emits dun.scheduled_event.processed notification" do
      world = create(:world, :grace)
      event = create(:scheduled_event, world: world, kind: "grace_expiry", fire_at: 1.minute.ago)

      captured = nil
      ActiveSupport::Notifications.subscribed(
        ->(_name, _start, _finish, _id, payload) { captured = payload },
        "dun.scheduled_event.processed"
      ) do
        Dispatch.call(event)
      end

      assert_equal "grace_expiry", captured[:kind]
      assert_equal event.id, captured[:event_id]
    end
  end
end
