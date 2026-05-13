module Worlds
  class StartJob < ApplicationJob
    queue_as :default

    def perform(world_id)
      world = World.find_by(id: world_id)
      return if world.nil?

      Worlds::Start.call(world)
    rescue Worlds::Start::WorldNotStartable => e
      Rails.logger.warn(event: "worlds.start_job.skipped", world_id: world_id, reason: e.message)
    end
  end
end
