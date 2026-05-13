module MapGeneration
  class BuildGraph
    Result = Struct.new(:regions, :adjacencies, keyword_init: true)

    REGION_NAMES_PATH = Rails.root.join("db", "seed_data", "region_names.yml")
    REGION_NAMES = YAML.load_file(REGION_NAMES_PATH).freeze

    MIN_DEGREE_TARGET = 2.8
    MAX_DEGREE_TARGET = 3.5
    MIN_DEGREE_HARD = 2

    def self.call(world:, players_count:, rng:)
      new(world: world, players_count: players_count, rng: rng).call
    end

    def initialize(world:, players_count:, rng:)
      @world = world
      @players_count = players_count
      @rng = rng
    end

    def call
      n = region_count
      points = sample_points(n)
      edges = Dun::Delaunay.edges_for(points.map { |x, y| { x: x, y: y } })
      edges = prune_to_target_degree(edges, points, n)
      names = sample_names(n)

      regions = persist_regions(points, names)
      adjacencies = persist_adjacencies(regions, edges)
      mark_hubs(regions, adjacencies)

      Result.new(regions: regions, adjacencies: adjacencies)
    end

    def region_count
      (2.5 * @players_count + 6).round.clamp(16, 64)
    end

    private

    def sample_points(n)
      target = []
      min_dist_sq = (0.65 / Math.sqrt(n))**2
      attempts = 0
      max_attempts = n * 200

      while target.size < n && attempts < max_attempts
        x = @rng.rand
        y = @rng.rand
        if target.all? { |px, py| (px - x)**2 + (py - y)**2 >= min_dist_sq }
          target << [ x, y ]
        end
        attempts += 1
      end

      while target.size < n
        target << [ @rng.rand, @rng.rand ]
      end

      target
    end

    def sample_names(n)
      REGION_NAMES.dup.shuffle(random: @rng).first(n)
    end

    def prune_to_target_degree(edges, points, n)
      degrees = Array.new(n, 0)
      edges.each { |i, j| degrees[i] += 1; degrees[j] += 1 }

      avg = (2.0 * edges.size) / n
      return edges if avg <= MAX_DEGREE_TARGET

      sorted = edges.sort_by do |i, j|
        -((points[i][0] - points[j][0])**2 + (points[i][1] - points[j][1])**2)
      end

      kept = edges.dup
      sorted.each do |i, j|
        break if (2.0 * kept.size) / n <= MIN_DEGREE_TARGET
        next if degrees[i] <= MIN_DEGREE_HARD || degrees[j] <= MIN_DEGREE_HARD
        kept.delete([ i, j ])
        degrees[i] -= 1
        degrees[j] -= 1
      end
      kept
    end

    def persist_regions(points, names)
      now = Time.current
      rows = points.each_with_index.map do |(x, y), i|
        {
          id: ULID.generate,
          world_id: @world.id,
          name: names[i],
          terrain: "plains",
          position: { "x" => x, "y" => y },
          spawn_eligible: false,
          is_hub: false,
          created_at: now,
          updated_at: now
        }
      end
      Region.insert_all!(rows)
      ids = rows.map { |r| r[:id] }
      by_id = Region.where(id: ids).index_by(&:id)
      ids.map { |id| by_id.fetch(id) }
    end

    def persist_adjacencies(regions, edges)
      now = Time.current
      rows = edges.map do |i, j|
        ra, rb = [ regions[i].id, regions[j].id ].sort
        { id: ULID.generate, region_a_id: ra, region_b_id: rb, created_at: now, updated_at: now }
      end
      RegionAdjacency.insert_all!(rows) if rows.any?
      RegionAdjacency.where(region_a_id: regions.map(&:id)).to_a
    end

    def mark_hubs(regions, adjacencies)
      counts = Hash.new(0)
      adjacencies.each do |a|
        counts[a.region_a_id] += 1
        counts[a.region_b_id] += 1
      end
      hub_ids = regions.select { |r| counts[r.id] >= 5 }.map(&:id)
      Region.where(id: hub_ids).update_all(is_hub: true) if hub_ids.any?
      regions.each { |r| r.is_hub = hub_ids.include?(r.id) }
    end
  end
end
