module Api
  module Worlds
    class RuinsController < Api::BaseController
      def index
        ruins = world.ruins.includes(:region).order("regions.name")
        render json: { ruins: ruins.map { |r| serialize(r) } }
      end

      private

      def world
        @world ||= begin
          w = World.find(params[:world_id])
          raise ActiveRecord::RecordNotFound, "world not visible" unless w.server.server_memberships.exists?(player_id: Current.player.id)
          w
        end
      end

      def serialize(ruin)
        {
          id: ruin.id,
          region_id: ruin.region_id,
          region_name: ruin.region.name,
          tier: ruin.tier,
          garrison: ruin.garrison,
          cache: ruin.cache,
          claimed: ruin.claimed?,
          claimed_by_kingdom_id: ruin.claimed_by_kingdom_id,
          claimed_at: ruin.claimed_at&.iso8601
        }
      end
    end
  end
end
