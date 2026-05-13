module Worlds
  class EndGraceJob < ApplicationJob
    queue_as :default

    def perform(world_id)
      world = World.find_by(id: world_id)
      return if world.nil?

      Worlds::EndGrace.call(world)
    end
  end
end
