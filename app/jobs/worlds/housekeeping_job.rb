module Worlds
  class HousekeepingJob < ApplicationJob
    queue_as :default

    PROCESSED_EVENT_TTL = 7.days

    def perform
      auto_cancel_stale_proposed_worlds
      eager_start_overdue_worlds
      close_overdue_grace_windows
      reap_old_processed_events
    end

    private

    def auto_cancel_stale_proposed_worlds
      World.where(status: "proposed").find_each do |world|
        deadline = world.created_at + world.auto_cancel_after_hours.hours
        next if Time.current < deadline
        next if world.kingdoms.count >= world.min_players

        world.update!(status: "cancelled", cancelled_at: Time.current)
        Rails.logger.info(event: "worlds.housekeeping.auto_cancelled", world_id: world.id)
      end
    end

    def eager_start_overdue_worlds
      World.where(status: "proposed").where("t0_at <= ?", Time.current).find_each do |world|
        Worlds::Start.call(world)
      rescue Worlds::Start::WorldNotStartable
        next
      end
    end

    def close_overdue_grace_windows
      World.where(status: "grace").where("grace_closes_at <= ?", Time.current).find_each do |world|
        Worlds::EndGrace.call(world)
      rescue => e
        Rails.logger.warn(event: "worlds.housekeeping.end_grace_failed", world_id: world.id, error_class: e.class.name, error_message: e.message)
      end
    end

    def reap_old_processed_events
      ScheduledEvent.processed.where("processed_at < ?", PROCESSED_EVENT_TTL.ago).delete_all
    end
  end
end
