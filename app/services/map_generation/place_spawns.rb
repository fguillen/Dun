module MapGeneration
  class InfeasibleSeed < StandardError; end

  class PlaceSpawns
    SPAWN_TERRAINS = Region::SPAWN_TERRAINS
    HUB_DEGREE = 5
    SPAWN_DEGREE_RANGE = (2..4)
    MIN_SPACING_HOPS = 2
    MIN_WILDERNESS_NEIGHBORS = 2
    RELAX_ATTEMPTS = 50

    Result = Struct.new(:spawn_regions, :home_hoards, keyword_init: true)

    def self.call(world:, players_count:, rng:)
      new(world: world, players_count: players_count, rng: rng).call
    end

    def initialize(world:, players_count:, rng:)
      @world = world
      @players_count = players_count
      @rng = rng
      @target_slots = (@players_count * 1.5).ceil
    end

    def call
      regions = @world.regions.order(:id).to_a
      adjacency = build_adjacency_map(regions)
      degree = adjacency.transform_values(&:size)

      hard_candidates = regions.select { |r| SPAWN_TERRAINS.include?(r.terrain) }

      raise InfeasibleSeed, "no spawn-terrain region for seed=#{@world.seed}" if hard_candidates.empty?

      spawns = pick_spawns(hard_candidates, adjacency, degree)

      verify_or_raise!(spawns)
      mark_spawn_eligible(spawns)
      home_hoards = place_home_hoards(spawns, adjacency)

      Result.new(spawn_regions: spawns, home_hoards: home_hoards)
    end

    private

    def build_adjacency_map(regions)
      ids = regions.map(&:id)
      map = ids.each_with_object({}) { |id, h| h[id] = [] }
      RegionAdjacency.where(region_a_id: ids).find_each do |adj|
        map[adj.region_a_id] << adj.region_b_id
        map[adj.region_b_id] << adj.region_a_id
      end
      map
    end

    def pick_spawns(candidates, adjacency, degree)
      best = []

      [ :none, :degree, :wilderness ].each do |relax|
        RELAX_ATTEMPTS.times do
          spawns = poisson_disk_pick(candidates, adjacency, degree, relax)
          best = spawns if spawns.size > best.size
          break if best.size >= @target_slots
        end
        break if best.size >= @target_slots
      end

      best.first(@target_slots)
    end

    def poisson_disk_pick(candidates, adjacency, degree, relax)
      spawns = []
      pool = candidates.shuffle(random: @rng)

      first = pool.find { |r| satisfies_relaxed?(r, adjacency, degree, spawns, relax) }
      return spawns if first.nil?
      spawns << first
      pool.delete(first)

      while spawns.size < @target_slots
        existing_ids = spawns.map(&:id)
        best = nil
        best_distance = -1
        pool.each do |c|
          next unless satisfies_relaxed?(c, adjacency, degree, spawns, relax)
          dist = min_hop_distance(c.id, existing_ids, adjacency)
          next if dist < MIN_SPACING_HOPS
          if dist > best_distance || (dist == best_distance && @rng.rand < 0.5)
            best = c
            best_distance = dist
          end
        end
        break if best.nil?
        spawns << best
        pool.delete(best)
      end

      spawns
    end

    def satisfies_relaxed?(region, adjacency, degree, spawns_so_far, relax)
      d = degree[region.id]
      degree_ok = case relax
                  when :none       then SPAWN_DEGREE_RANGE.cover?(d)
                  when :degree     then d.between?(2, HUB_DEGREE)
                  else                  d >= 1
      end

      spawn_id_set = spawns_so_far.map(&:id).to_set
      wilderness_neighbors = adjacency[region.id].count { |id| !spawn_id_set.include?(id) }
      wilderness_ok = wilderness_neighbors >= MIN_WILDERNESS_NEIGHBORS || relax == :wilderness

      degree_ok && wilderness_ok
    end

    def min_hop_distance(start_id, target_ids, adjacency)
      return Float::INFINITY if target_ids.empty?

      seen = { start_id => 0 }
      frontier = [ start_id ]
      depth = 0
      target_set = target_ids.to_set

      until frontier.empty?
        depth += 1
        next_frontier = []
        frontier.each do |id|
          adjacency[id].each do |nb|
            next if seen.key?(nb)
            return depth if target_set.include?(nb)
            seen[nb] = depth
            next_frontier << nb
          end
        end
        frontier = next_frontier
      end
      Float::INFINITY
    end

    def verify_or_raise!(spawns)
      return if spawns.size >= @target_slots

      Rails.logger.warn(
        event: "map_generation.spawn_relaxation_short",
        world_id: @world.id,
        seed: @world.seed,
        requested_slots: @target_slots,
        placed_slots: spawns.size
      )

      raise InfeasibleSeed, "no spawn slots placed for seed=#{@world.seed}" if spawns.empty?
    end

    def mark_spawn_eligible(spawns)
      Region.where(id: spawns.map(&:id)).update_all(spawn_eligible: true)
      spawns.each { |r| r.spawn_eligible = true }
    end

    def place_home_hoards(spawns, adjacency)
      now = Time.current
      rows = spawns.map do |spawn|
        resource = pick_home_hoard_resource(spawn, adjacency)
        {
          region_id: spawn.id,
          resource: resource,
          tier: "standard",
          base_rate: Node::TIER_BASE_RATE["standard"],
          garrison: Node::WILDERNESS_GARRISONS["standard"],
          is_home_hoard: true,
          created_at: now,
          updated_at: now
        }
      end
      Node.insert_all!(rows) if rows.any?
      Node.where(region_id: spawns.map(&:id), is_home_hoard: true).to_a
    end

    def pick_home_hoard_resource(spawn, adjacency)
      neighbor_ids = adjacency[spawn.id]
      counts = Kingdom::RESOURCES.index_with { 0 }
      @world.nodes.where(region_id: neighbor_ids).pluck(:resource).each do |r|
        counts[r] += 1 if counts.key?(r)
      end
      counts.min_by { |_, c| [ c, @rng.rand ] }.first
    end
  end
end
