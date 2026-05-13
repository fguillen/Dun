module MapGeneration
  class PlaceNodes
    TIER_SHARES = { "rich" => 0.20, "standard" => 0.50, "poor" => 0.30 }.freeze
    RESOURCE_SHARES = { "stone" => 0.35, "iron" => 0.25, "wood" => 0.20, "gold" => 0.20 }.freeze
    THEMATIC_TERRAINS = {
      "iron"  => %w[mountain hills],
      "stone" => %w[mountain hills],
      "wood"  => %w[forest],
      "gold"  => %w[plains hills]
    }.freeze
    THEMATIC_BIAS = 0.70

    def self.call(world:, players_count:, rng:)
      new(world: world, players_count: players_count, rng: rng).call
    end

    def initialize(world:, players_count:, rng:)
      @world = world
      @players_count = players_count
      @rng = rng
    end

    def call
      total = (1.2 * @players_count).round
      tiers = allocate_by_share(total, TIER_SHARES)
      resources = allocate_by_share(total, RESOURCE_SHARES)
      tiers.shuffle!(random: @rng)
      resources.shuffle!(random: @rng)

      all_regions = @world.regions.order(:id).to_a
      spawn_ids = all_regions.select(&:spawn_eligible).map(&:id).to_set
      spawn_adjacent_ids = compute_spawn_adjacent_ids(all_regions, spawn_ids)
      eligible = all_regions.reject { |r| spawn_ids.include?(r.id) }

      region_nodes = Hash.new { |h, k| h[k] = [] }
      rows = []

      total.times do |i|
        tier = tiers[i]
        resource = resources[i]
        region = pick_region(eligible, region_nodes, resource, tier, spawn_adjacent_ids)
        next if region.nil?

        region_nodes[region.id] << { resource: resource, tier: tier }
        rows << build_row(region, resource, tier)
      end

      Node.insert_all!(rows) if rows.any?
      @world.reload
      @world.nodes.where(is_home_hoard: false).to_a
    end

    private

    def allocate_by_share(total, shares)
      counts = shares.transform_values { |share| (share * total).round }
      diff = total - counts.values.sum
      keys = shares.keys
      diff.times { |i| counts[keys[i % keys.size]] += diff.positive? ? 1 : -1 }
      counts.flat_map { |kind, count| [ kind ] * count }
    end

    def pick_region(regions, region_nodes, resource, tier, spawn_adjacent_ids)
      eligible = regions.select { |r| eligible?(r, region_nodes, tier, spawn_adjacent_ids) }
      return nil if eligible.empty?

      thematic = THEMATIC_TERRAINS[resource]
      preferred = eligible.select { |r| thematic.include?(r.terrain) }

      use_thematic = preferred.any? && @rng.rand < THEMATIC_BIAS
      pool = use_thematic ? preferred : eligible
      pool.shuffle(random: @rng).first
    end

    def eligible?(region, region_nodes, tier, spawn_adjacent_ids)
      existing = region_nodes[region.id]
      return false if existing.size >= 2
      return false if tier == "rich" && existing.any?
      return false if existing.any? { |n| n[:tier] == "rich" }
      return false if tier == "rich" && spawn_adjacent_ids.include?(region.id)

      true
    end

    def compute_spawn_adjacent_ids(all_regions, spawn_ids)
      ids = all_regions.map(&:id)
      adjacency_rows = RegionAdjacency.where(region_a_id: ids).pluck(:region_a_id, :region_b_id)
      adjacent = Set.new
      adjacency_rows.each do |a_id, b_id|
        adjacent << b_id if spawn_ids.include?(a_id)
        adjacent << a_id if spawn_ids.include?(b_id)
      end
      adjacent
    end

    def build_row(region, resource, tier)
      now = Time.current
      {
        region_id: region.id,
        resource: resource,
        tier: tier,
        base_rate: Node::TIER_BASE_RATE[tier],
        garrison: Node::WILDERNESS_GARRISONS[tier],
        is_home_hoard: false,
        created_at: now,
        updated_at: now
      }
    end
  end
end
