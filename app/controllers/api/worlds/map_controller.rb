module Api
  module Worlds
    class MapController < Api::BaseController
      def index
        regions = world.regions.includes(:nodes, :ruin).order(:name)
        adjacency = build_adjacency(regions)
        my_spawn_id = my_kingdoms_spawn_id

        render json: {
          regions: regions.map { |r| serialize(r, adjacency, my_spawn_id) }
        }
      end

      private

      def world
        @world ||= begin
          w = World.find(params[:world_id])
          raise ActiveRecord::RecordNotFound, "world not visible" unless w.server.server_memberships.exists?(player_id: Current.player.id)
          w
        end
      end

      def build_adjacency(regions)
        ids = regions.map(&:id)
        map = ids.each_with_object({}) { |id, h| h[id] = [] }
        RegionAdjacency.where(region_a_id: ids).pluck(:region_a_id, :region_b_id).each do |a, b|
          map[a] << b
          map[b] << a
        end
        map
      end

      def my_kingdoms_spawn_id
        profile = PlayerProfile.find_by(server: world.server, player: Current.player)
        return nil unless profile

        world.kingdoms.where(player_profile_id: profile.id).pick(:home_region_id)
      end

      def serialize(region, adjacency, my_spawn_id)
        {
          id: region.id,
          name: region.name,
          terrain: region.terrain,
          position: region.position,
          is_hub: region.is_hub,
          spawn_eligible: region.spawn_eligible,
          your_spawn: region.id == my_spawn_id,
          adjacency: adjacency[region.id].sort,
          nodes: region.nodes.map { |n| { id: n.id, resource: n.resource, tier: n.tier, is_home_hoard: n.is_home_hoard } },
          ruin: region.ruin && { id: region.ruin.id, tier: region.ruin.tier, claimed: region.ruin.claimed? }
        }
      end
    end
  end
end
