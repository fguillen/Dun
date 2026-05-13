module Worlds
  class EndGrace
    def self.call(world)
      new(world).call
    end

    def initialize(world)
      @world = world
    end

    def call
      ActiveRecord::Base.transaction do
        world = World.lock.find(@world.id)
        return world unless world.grace?

        unused_spawn_ids = world.regions
          .where(spawn_eligible: true)
          .where.not(id: world.kingdoms.where.not(home_region_id: nil).select(:home_region_id))
          .pluck(:id)
        Region.where(id: unused_spawn_ids).update_all(spawn_eligible: false) if unused_spawn_ids.any?

        world.update!(status: "active")
        world
      end
    end
  end
end
