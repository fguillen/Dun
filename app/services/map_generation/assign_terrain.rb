module MapGeneration
  class AssignTerrain
    TARGET_SHARES = {
      "plains"   => 0.40,
      "forest"   => 0.20,
      "hills"    => 0.20,
      "mountain" => 0.12,
      "marsh"    => 0.08
    }.freeze

    def self.call(world:, rng:)
      new(world: world, rng: rng).call
    end

    def initialize(world:, rng:)
      @world = world
      @rng = rng
    end

    def call
      regions = @world.regions.order(:name).to_a
      total = regions.size

      seed_terrains = build_seed_pool(total)
      seeds = pick_seeds(regions, seed_terrains)
      assignments = voronoi_assign(regions, seeds)
      apply_assignments(assignments)
      regions.each { |r| r.terrain = assignments[r.id] }
      regions
    end

    private

    def build_seed_pool(total)
      cluster_size = 4.0
      pool = []
      TARGET_SHARES.each do |terrain, share|
        count = [ (share * total / cluster_size).round, 1 ].max
        count.times { pool << terrain }
      end
      pool.shuffle(random: @rng)
    end

    def pick_seeds(regions, terrains)
      sampled = regions.dup.shuffle(random: @rng).first(terrains.size)
      sampled.zip(terrains).map { |region, terrain| { region: region, terrain: terrain } }
    end

    def voronoi_assign(regions, seeds)
      assignments = {}
      regions.each do |r|
        rx = r.position["x"]
        ry = r.position["y"]
        nearest = seeds.min_by do |seed|
          sx = seed[:region].position["x"]
          sy = seed[:region].position["y"]
          (rx - sx)**2 + (ry - sy)**2
        end
        assignments[r.id] = nearest[:terrain]
      end
      assignments
    end

    def apply_assignments(assignments)
      grouped = assignments.group_by { |_, terrain| terrain }
      grouped.each do |terrain, pairs|
        ids = pairs.map(&:first)
        Region.where(id: ids).update_all(terrain: terrain)
      end
    end
  end
end
