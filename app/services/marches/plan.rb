module Marches
  class Plan
    class EmptyArmy < StandardError; end
    class CrossWorld < StandardError; end
    class Unreachable < StandardError; end

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

      adjacency = TravelGraph.adjacency_for(@origin.world)
      predecessors = TravelGraph.shortest_paths_from(@origin.id, adjacency)
      path_ids = TravelGraph.path_to(predecessors, @destination.id)
      raise Unreachable, "no path from #{@origin.id} to #{@destination.id}" if path_ids.nil?

      regions = @origin.world.regions.where(id: path_ids).index_by(&:id)
      slowest = @army.slowest_speed
      immune = @army.all_terrain_immune?

      legs = []
      total = 0.0
      path_ids.each_cons(2) do |from_id, to_id|
        from = regions[from_id]
        to = regions[to_id]
        terrain_avg = TravelGraph.terrain_avg(from, to, immune)
        leg_seconds = TravelGraph.leg_seconds(from, to, slowest, immune)
        legs << Leg.new(from: from_id, to: to_id, terrain_avg: terrain_avg, seconds: leg_seconds)
        total += leg_seconds
      end

      Result.new(path: path_ids, total_seconds: total, per_leg: legs)
    end
  end
end
