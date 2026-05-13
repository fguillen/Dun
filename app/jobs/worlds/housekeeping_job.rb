module Worlds
  class HousekeepingJob < ApplicationJob
    queue_as :default

    def perform
      auto_cancel_stale_proposed_worlds
      eager_start_overdue_worlds
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
  end
end
