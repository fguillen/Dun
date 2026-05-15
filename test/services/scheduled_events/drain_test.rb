require "test_helper"

module ScheduledEvents
  class DrainTest < ActiveSupport::TestCase
    test "processes only ripe events in fire_at, id order" do
      world = create(:world, :grace)
      future = create(:scheduled_event, world: world, kind: "grace_expiry", fire_at: 1.hour.from_now)
      ripe   = create(:scheduled_event, world: world, kind: "grace_expiry", fire_at: 5.minutes.ago)

      Drain.call

      assert ripe.reload.processed_at.present?
      assert future.reload.pending?
    end

    test "errors in one handler do not abort the batch" do
      good_world = create(:world, :grace)
      bad_world  = create(:world, :active)

      bad = ScheduledEvent.create!(world: bad_world, kind: "weather_edge", fire_at: 1.minute.ago)
      good = create(:scheduled_event, world: good_world, kind: "grace_expiry", fire_at: 30.seconds.ago)

      Drain.call

      assert good.reload.processed_at.present?
      assert bad.reload.pending?
    end

    test "late events (fire_at well in the past) still fire" do
      world = create(:world, :grace)
      stale = create(:scheduled_event, world: world, kind: "grace_expiry", fire_at: 5.hours.ago)

      Drain.call

      assert stale.reload.processed_at.present?
    end

    test "double drain does not reprocess (event marked processed once)" do
      world = create(:world, :grace)
      event = create(:scheduled_event, world: world, kind: "grace_expiry", fire_at: 1.minute.ago)

      Drain.call
      first = event.reload.processed_at
      Drain.call
      assert_equal first, event.reload.processed_at
    end
  end
end
