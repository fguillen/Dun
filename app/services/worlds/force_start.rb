module Worlds
  class ForceStart
    class WorldNotForceStartable < StandardError; end

    def self.call(world)
      new(world).call
    end

    def initialize(world)
      @world = world
    end

    def call
      ActiveRecord::Base.transaction do
        world = World.lock.find(@world.id)
        raise WorldNotForceStartable, "world is #{world.status}; only proposed worlds can be force-started" unless world.proposed?

        now = Time.current
        pre_t0_kingdoms = world.kingdoms.where(home_region_id: nil).to_a

        MapGeneration::Generate.call(world: world, players_count: pre_t0_kingdoms.size)

        assign_t0_kingdoms(world, pre_t0_kingdoms)

        world.update!(
          status: "grace",
          t0_at: now,
          grace_closes_at: now + Worlds::Start::GRACE_WINDOW
        )

        Worlds::EndGraceJob.set(wait_until: world.grace_closes_at).perform_later(world.id)

        world
      end
    end

    private

    def assign_t0_kingdoms(world, kingdoms)
      kingdoms.sort_by(&:joined_at).each do |kingdom|
        MapGeneration::AssignLateJoiner.call(
          world: world,
          player_profile: kingdom.player_profile,
          hours_since_t0: 0
        )
      end
    end
  end
end
