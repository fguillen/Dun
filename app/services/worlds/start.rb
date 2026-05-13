module Worlds
  class Start
    class WorldNotStartable < StandardError; end

    GRACE_WINDOW = 72.hours

    def self.call(world)
      new(world).call
    end

    def initialize(world)
      @world = world
    end

    def call
      ActiveRecord::Base.transaction do
        world = World.lock.find(@world.id)
        return world unless world.proposed?
        return world if Time.current < world.t0_at

        pre_t0_kingdoms = world.kingdoms.where(home_region_id: nil).to_a
        if pre_t0_kingdoms.size < world.min_players
          raise WorldNotStartable, "world #{world.id} has #{pre_t0_kingdoms.size} joiners, needs #{world.min_players}"
        end

        MapGeneration::Generate.call(world: world, players_count: pre_t0_kingdoms.size)

        assign_t0_kingdoms(world, pre_t0_kingdoms)

        world.update!(status: "grace", grace_closes_at: world.t0_at + GRACE_WINDOW)

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
