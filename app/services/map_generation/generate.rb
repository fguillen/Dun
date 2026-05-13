module MapGeneration
  class Generate
    def self.call(world:, players_count:)
      new(world: world, players_count: players_count).call
    end

    def initialize(world:, players_count:)
      @world = world
      @players_count = players_count
    end

    def call
      rng = Random.new(@world.seed_int)

      ActiveRecord::Base.transaction do
        BuildGraph.call(world: @world, players_count: @players_count, rng: rng)
        AssignTerrain.call(world: @world, rng: rng)
      end

      @world.reload
    end
  end
end
