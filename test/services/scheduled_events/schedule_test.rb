require "test_helper"

module ScheduledEvents
  class ScheduleTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
    end

    test "creates a pending ScheduledEvent" do
      fire_at = 1.hour.from_now
      event = Schedule.call(world: @world, kind: "build_completion", fire_at: fire_at, payload: { foo: "bar" })

      assert_equal @world.id, event.world_id
      assert_equal "build_completion", event.kind
      assert_equal({ "foo" => "bar" }, event.payload)
      assert_in_delta fire_at, event.fire_at, 1
      assert event.pending?
    end

    test "emits dun.scheduled_event.created notification" do
      captured = nil
      ActiveSupport::Notifications.subscribed(
        ->(_name, _start, _finish, _id, payload) { captured = payload },
        "dun.scheduled_event.created"
      ) do
        Schedule.call(world: @world, kind: "build_completion", fire_at: 1.minute.from_now)
      end

      assert_equal "build_completion", captured[:kind]
      assert_equal @world.id, captured[:world_id]
    end

    test "stringifies symbol payload keys" do
      event = Schedule.call(world: @world, kind: "build_completion", fire_at: 1.minute.from_now, payload: { build_order_id: "abc" })
      assert_equal({ "build_order_id" => "abc" }, event.payload)
    end
  end
end
