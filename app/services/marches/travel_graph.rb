module Marches
  # Shared travel math for the region adjacency graph (§16.10, §16.3): the single
  # source of truth for path-finding and per-leg duration so a march preview
  # matches an actual dispatch exactly. Consumed by both Marches::Plan (single
  # destination) and Marches::BulkPreview (every destination at once).
  class TravelGraph
    BFS_NODE_CAP = 1_000

    # Undirected adjacency hash {region_id => [neighbor_ids]} for a world.
    def self.adjacency_for(world)
      ids = world.regions.pluck(:id)
      pairs = RegionAdjacency.where(region_a_id: ids).pluck(:region_a_id, :region_b_id)
      adjacency = Hash.new { |h, k| h[k] = [] }
      pairs.each do |a, b|
        adjacency[a] << b
        adjacency[b] << a
      end
      adjacency
    end

    # Single-source BFS. Returns a predecessor map {region_id => prev_id} with the
    # origin mapped to nil. Unreachable regions are absent from the map. Caps the
    # search at BFS_NODE_CAP visited nodes.
    def self.shortest_paths_from(origin_id, adjacency, node_cap: BFS_NODE_CAP)
      predecessors = { origin_id => nil }
      queue = [ origin_id ]

      while (current = queue.shift)
        break if predecessors.size > node_cap
        (adjacency[current] || []).each do |neighbor|
          next if predecessors.key?(neighbor)
          predecessors[neighbor] = current
          queue << neighbor
        end
      end

      predecessors
    end

    # Reconstruct the [origin..target] path from a predecessor map, or nil if the
    # target was never reached.
    def self.path_to(predecessors, target_id)
      return nil unless predecessors.key?(target_id)

      path = [ target_id ]
      while (prev = predecessors[path.first])
        path.unshift(prev)
      end
      path
    end

    # Average terrain march modifier across a leg's two endpoints. Knight/Scout-only
    # armies ignore terrain (1.0); otherwise it is the mean of the two endpoints'
    # Region::TERRAIN_MARCH_MOD.
    def self.terrain_avg(from_region, to_region, immune)
      return 1.0 if immune

      (Region::TERRAIN_MARCH_MOD[from_region.terrain] + Region::TERRAIN_MARCH_MOD[to_region.terrain]) / 2.0
    end

    # Per-leg travel time in seconds. Base leg is one hour at speed 1 / terrain 1.
    def self.leg_seconds(from_region, to_region, slowest_speed, immune)
      (1.0 / (slowest_speed * terrain_avg(from_region, to_region, immune))) * 3600
    end
  end
end
