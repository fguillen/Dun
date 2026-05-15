require "test_helper"

module Worlds
  class HousekeepingJobTest < ActiveJob::TestCase
    test "auto-cancels a proposed world past its auto_cancel_after_hours with too few joiners" do
      world = create(:world, status: "proposed", auto_cancel_after_hours: 1, min_players: 4)
      world.update_columns(created_at: 2.hours.ago)

      Worlds::HousekeepingJob.perform_now

      world.reload
      assert_equal "cancelled", world.status
      assert_not_nil world.cancelled_at
    end

    test "does not cancel a proposed world that has met its min_players" do
      world = create(:world, status: "proposed", auto_cancel_after_hours: 1, min_players: 2)
      world.update_columns(created_at: 2.hours.ago)
      2.times do
        profile = create(:player_profile, server: world.server)
        Kingdom.create!(world: world, player_profile: profile, home_region: nil, joined_at: Time.current)
      end

      Worlds::HousekeepingJob.perform_now
      assert_equal "proposed", world.reload.status
    end

    test "leaves a still-young proposed world alone" do
      world = create(:world, status: "proposed", auto_cancel_after_hours: 168)
      Worlds::HousekeepingJob.perform_now
      assert_equal "proposed", world.reload.status
    end

    test "closes a grace window whose grace_closes_at has passed (safety net)" do
      world = create(:world, :grace)
      world.update_columns(grace_closes_at: 5.minutes.ago)

      Worlds::HousekeepingJob.perform_now

      assert_equal "active", world.reload.status
    end

    test "leaves a still-open grace window alone" do
      world = create(:world, :grace)
      world.update_columns(grace_closes_at: 1.hour.from_now)
      Worlds::HousekeepingJob.perform_now
      assert_equal "grace", world.reload.status
    end

    test "reaps ScheduledEvents whose processed_at is older than 7 days" do
      world = create(:world, :active)
      old_event = create(:scheduled_event, world: world, kind: "build_completion", fire_at: 8.days.ago, processed_at: 8.days.ago)
      recent_event = create(:scheduled_event, world: world, kind: "build_completion", fire_at: 1.day.ago, processed_at: 1.day.ago)
      pending_event = create(:scheduled_event, world: world, kind: "build_completion", fire_at: 1.minute.ago)

      Worlds::HousekeepingJob.perform_now

      refute ScheduledEvent.exists?(old_event.id)
      assert ScheduledEvent.exists?(recent_event.id)
      assert ScheduledEvent.exists?(pending_event.id)
    end
  end
end
