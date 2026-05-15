module Marches
  class Plan
    class EmptyArmy < StandardError; end
    class CrossWorld < StandardError; end
    class Unreachable < StandardError; end

    BFS_NODE_CAP = 1_000

    Result = Struct.new(:path, :total_seconds, :per_leg, keyword_init: true)
    Leg = Struct.new(:from, :to, :terrain_avg, :seconds, keyword_init: true)

    def self.call(origin:, destination:, army:)
      new(origin: origin, destination: destination, army: army).call
    end

    def initialize(origin:, destination:, army:)
      @origin = origin
      @destination = destination
      @army = army
    end

    def call
      raise EmptyArmy, "army has no units" if @army.empty?
      raise CrossWorld, "origin and destination must be in the same world" if @origin.world_id != @destination.world_id

      path_ids = bfs_path
      raise Unreachable, "no path from #{@origin.id} to #{@destination.id}" if path_ids.nil?

      regions = @origin.world.regions.where(id: path_ids).index_by(&:id)
      slowest = @army.slowest_speed
      immune = @army.all_terrain_immune?

      legs = []
      total = 0.0
      path_ids.each_cons(2) do |from_id, to_id|
        from = regions[from_id]
        to = regions[to_id]
        terrain_avg = if immune
          1.0
        else
          (Region::TERRAIN_MARCH_MOD[from.terrain] + Region::TERRAIN_MARCH_MOD[to.terrain]) / 2.0
        end
        leg_seconds = (1.0 / (slowest * terrain_avg)) * 3600
        legs << Leg.new(from: from_id, to: to_id, terrain_avg: terrain_avg, seconds: leg_seconds)
        total += leg_seconds
      end

      Result.new(path: path_ids, total_seconds: total, per_leg: legs)
    end

    private

    def bfs_path
      return [ @origin.id ] if @origin.id == @destination.id

      adjacency = build_adjacency
      visited = { @origin.id => nil }
      queue = [ @origin.id ]

      while (current = queue.shift)
        return false if visited.size > BFS_NODE_CAP
        (adjacency[current] || []).each do |neighbor|
          next if visited.key?(neighbor)
          visited[neighbor] = current
          if neighbor == @destination.id
            return reconstruct(visited, neighbor)
          end
          queue << neighbor
        end
      end

      nil
    end

    def build_adjacency
      world_region_ids = @origin.world.regions.pluck(:id)
      pairs = RegionAdjacency.where(region_a_id: world_region_ids).pluck(:region_a_id, :region_b_id)
      adjacency = Hash.new { |h, k| h[k] = [] }
      pairs.each do |a, b|
        adjacency[a] << b
        adjacency[b] << a
      end
      adjacency
    end

    def reconstruct(visited, target)
      path = [ target ]
      while (prev = visited[path.first])
        path.unshift(prev)
      end
      path
    end
  end
end
