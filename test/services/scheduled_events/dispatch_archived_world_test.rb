require "test_helper"

module ScheduledEvents
  class DispatchArchivedWorldTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :archived)
      @event = create(:scheduled_event,
        world: @world,
        kind: "build_completion",
        fire_at: 1.minute.ago,
        payload: { "build_order_id" => "nonexistent" })
    end

    test "skips events for archived worlds and stamps processed_at" do
      events = []
      ActiveSupport::Notifications.subscribed(->(name, _, _, _, p) { events << [ name, p ] }, /dun\.scheduled_event\./) do
        Dispatch.call(@event)
      end
      @event.reload
      assert_not_nil @event.processed_at
      assert_includes events.map(&:first), "dun.scheduled_event.skipped_world_archived"
    end
  end
end
