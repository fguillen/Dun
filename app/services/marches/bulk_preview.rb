module Marches
  # Read-only bulk march ETA for the client's map view: for every army a kingdom
  # owns, the travel time to every region on the world. Shares Marches::TravelGraph
  # with Marches::Dispatch so a preview equals the actual dispatch (§16.10). Builds
  # the adjacency graph once and runs a single BFS per army.
  class BulkPreview
    def self.call(kingdom:)
      new(kingdom: kingdom).call
    end

    def initialize(kingdom:)
      @kingdom = kingdom
      @now = Time.current
    end

    def call
      world = @kingdom.world
      regions = world.regions.to_a
      regions_by_id = regions.index_by(&:id)
      adjacency = TravelGraph.adjacency_for(world)

      armies = @kingdom.armies.order(:created_at)

      { army_previews: armies.map { |army| preview_army(army, regions, regions_by_id, adjacency) } }
    end

    private

    def preview_army(army, regions, regions_by_id, adjacency)
      {
        army_id: army.id,
        army_name: army.name,
        regions: army.empty? ? unreachable_everywhere(regions) : reachable_regions(army, regions, regions_by_id, adjacency)
      }
    end

    def unreachable_everywhere(regions)
      regions.map { |region| { region_id: region.id, reachable: false } }
    end

    def reachable_regions(army, regions, regions_by_id, adjacency)
      slowest = army.slowest_speed
      immune = army.all_terrain_immune?
      predecessors = TravelGraph.shortest_paths_from(army.location_region_id, adjacency)

      regions.map do |region|
        path = TravelGraph.path_to(predecessors, region.id)
        next { region_id: region.id, reachable: false } if path.nil?

        seconds = path_seconds(path, regions_by_id, slowest, immune)
        {
          region_id: region.id,
          reachable: true,
          hops: path.length - 1,
          duration_seconds: seconds.round,
          arrives_at: (@now + seconds).iso8601
        }
      end
    end

    def path_seconds(path, regions_by_id, slowest, immune)
      total = 0.0
      path.each_cons(2) do |from_id, to_id|
        total += TravelGraph.leg_seconds(regions_by_id[from_id], regions_by_id[to_id], slowest, immune)
      end
      total
    end
  end
end
