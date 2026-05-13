module Api
  module Worlds
    class RegionsController < Api::BaseController
      def show
        region = region_in_visible_world
        render json: serialize(region)
      end

      def adjacent
        region = region_in_visible_world
        ids = adjacency_ids_for(region)
        adj_regions = world.regions.where(id: ids).order(:name)
        render json: { regions: adj_regions.map { |r| short(r) } }
      end

      private

      def world
        @world ||= begin
          w = World.find(params[:world_id])
          raise ActiveRecord::RecordNotFound, "world not visible" unless w.server.server_memberships.exists?(player_id: Current.player.id)
          w
        end
      end

      def region_in_visible_world
        world.regions.find(params[:id])
      end

      def adjacency_ids_for(region)
        a = RegionAdjacency.where(region_a_id: region.id).pluck(:region_b_id)
        b = RegionAdjacency.where(region_b_id: region.id).pluck(:region_a_id)
        (a + b).uniq
      end

      def serialize(region)
        {
          id: region.id,
          name: region.name,
          terrain: region.terrain,
          position: region.position,
          is_hub: region.is_hub,
          spawn_eligible: region.spawn_eligible,
          adjacency: adjacency_ids_for(region).sort,
          nodes: region.nodes.map { |n|
            {
              id: n.id,
              resource: n.resource,
              tier: n.tier,
              base_rate: n.base_rate,
              is_home_hoard: n.is_home_hoard,
              owner_kingdom_id: n.owner_kingdom_id
            }
          },
          ruin: region.ruin && {
            id: region.ruin.id,
            tier: region.ruin.tier,
            claimed: region.ruin.claimed?,
            claimed_by_kingdom_id: region.ruin.claimed_by_kingdom_id
          },
          owner_kingdom_id: region.nodes.find { |n| n.is_home_hoard }&.owner_kingdom_id
        }
      end

      def short(region)
        { id: region.id, name: region.name, terrain: region.terrain }
      end
    end
  end
end
