module Api
  module Worlds
    class NodesController < Api::BaseController
      def index
        nodes = world.nodes.includes(:region).order("regions.name")
        render json: { nodes: nodes.map { |n| serialize(n) } }
      end

      def show
        node = world.nodes.includes(:region).find(params[:id])
        render json: { node: serialize(node) }
      end

      private

      def world
        @world ||= begin
          w = World.find(params[:world_id])
          raise ActiveRecord::RecordNotFound, "world not visible" unless w.server.server_memberships.exists?(player_id: Current.player.id)
          w
        end
      end

      def serialize(node)
        {
          id: node.id,
          region_id: node.region_id,
          region_name: node.region.name,
          resource: node.resource,
          tier: node.tier,
          base_rate: node.base_rate,
          is_home_hoard: node.is_home_hoard,
          owner_kingdom_id: node.owner_kingdom_id,
          garrison: node.garrison
        }
      end
    end
  end
end
