module MapGeneration
  class AssignLateJoiner
    class NoSpawnSlotAvailable < StandardError; end

    def self.call(world:, player_profile:, hours_since_t0:)
      new(world: world, player_profile: player_profile, hours_since_t0: hours_since_t0).call
    end

    def initialize(world:, player_profile:, hours_since_t0:)
      @world = world
      @profile = player_profile
      @hours_since_t0 = hours_since_t0
    end

    def call
      ActiveRecord::Base.transaction do
        existing = @world.kingdoms.find_by(player_profile_id: @profile.id)
        return assign_existing(existing) if existing&.home_region_id

        spawn_region = pick_spawn_region
        raise NoSpawnSlotAvailable, "no spawn region available in world #{@world.id}" if spawn_region.nil?

        kingdom = existing || @world.kingdoms.build(player_profile: @profile)
        kingdom.home_region = spawn_region
        kingdom.save!
        Kingdoms::Bootstrap.call(kingdom, hours_since_t0: @hours_since_t0)
        kingdom
      end
    end

    private

    def assign_existing(kingdom)
      Kingdoms::Bootstrap.call(kingdom, hours_since_t0: @hours_since_t0)
      kingdom
    end

    def pick_spawn_region
      claimed_ids = @world.kingdoms.where.not(home_region_id: nil).pluck(:home_region_id).to_set
      available = @world.regions.where(spawn_eligible: true).where.not(id: claimed_ids).to_a
      return nil if available.empty?

      rng = Random.new(@world.seed_int ^ @profile.id)
      available.shuffle(random: rng).first
    end
  end
end
