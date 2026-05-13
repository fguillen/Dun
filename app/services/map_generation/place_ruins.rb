module MapGeneration
  class PlaceRuins
    TIER_SHARES = { "minor" => 0.50, "standard" => 0.35, "major" => 0.15 }.freeze
    EXCLUDED_TERRAINS = %w[mountain marsh].freeze
    MIN_SPACING_HOPS = 2

    def self.call(world:, players_count:, rng:)
      new(world: world, players_count: players_count, rng: rng).call
    end

    def initialize(world:, players_count:, rng:)
      @world = world
      @players_count = players_count
      @rng = rng
    end

    def call
      target_count = [ 2, (@players_count / 4.0).round ].max
      regions = @world.regions.includes(:nodes).order(:id).to_a
      adjacency = build_adjacency_map(regions)
      spawn_ids = regions.select(&:spawn_eligible).map(&:id).to_set
      node_region_ids = @world.nodes.distinct.pluck(:region_id).to_set

      candidates = regions.select do |r|
        next false if EXCLUDED_TERRAINS.include?(r.terrain)
        next false if node_region_ids.include?(r.id)
        next false if spawn_ids.include?(r.id)

        true
      end

      placed = pick_ruins_with_spacing(candidates, adjacency, spawn_ids, target_count)
      tiers = allocate_tier_pool(placed.size).shuffle(random: @rng)

      now = Time.current
      rows = placed.each_with_index.map do |region, i|
        tier = tiers[i]
        {
          region_id: region.id,
          tier: tier,
          garrison: Ruin::GARRISONS[tier],
          cache: Ruin::CACHES[tier],
          created_at: now,
          updated_at: now
        }
      end

      Ruin.insert_all!(rows) if rows.any?
      @world.reload.ruins.to_a
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

    def pick_ruins_with_spacing(candidates, adjacency, _spawn_ids, target_count)
      placed = []
      pool = candidates.shuffle(random: @rng)
      pool.each do |region|
        break if placed.size >= target_count
        next if min_hops(region.id, placed.map(&:id), adjacency) < MIN_SPACING_HOPS
        placed << region
      end
      placed
    end

    def min_hops(start_id, target_ids, adjacency)
      return Float::INFINITY if target_ids.empty?

      target_set = target_ids.to_set
      seen = { start_id => 0 }
      frontier = [ start_id ]
      depth = 0
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

    def allocate_tier_pool(total)
      counts = TIER_SHARES.transform_values { |s| (s * total).round }
      diff = total - counts.values.sum
      keys = TIER_SHARES.keys
      diff.abs.times { |i| counts[keys[i % keys.size]] += diff.positive? ? 1 : -1 }
      counts.flat_map { |tier, c| [ tier ] * c }
    end
  end
end
