require "test_helper"

module ScheduledEvents
  class CancelTest < ActiveSupport::TestCase
    test "marks pending event as processed" do
      event = create(:scheduled_event)
      Cancel.call(event)
      assert event.reload.processed_at.present?
    end

    test "no-op on already-processed event" do
      event = create(:scheduled_event, processed_at: 1.minute.ago)
      original_processed_at = event.processed_at
      Cancel.call(event)
      assert_in_delta original_processed_at, event.reload.processed_at, 1
    end

    test "tolerates nil" do
      assert_nothing_raised { Cancel.call(nil) }
    end
  end
end
