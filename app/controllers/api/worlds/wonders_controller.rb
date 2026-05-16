module Api
  module Worlds
    class WondersController < Api::BaseController
      def index
        world = load_visible_world
        wonders = ::Wonder
          .joins(:kingdom)
          .where(kingdoms: { world_id: world.id })
          .order(:created_at)

        items = wonders.map { |w| serialize_item(w) }
        render json: { wonders: items }
      end

      private

      def load_visible_world
        world = ::World.find(params[:world_id])
        membership = ::ServerMembership.exists?(server_id: world.server_id, player_id: Current.player.id)
        raise ActiveRecord::RecordNotFound, "world not visible" unless membership

        world
      end

      def serialize_item(wonder)
        handle = wonder.kingdom.player_profile.handle
        {
          id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          builder_handle: handle,
          name: wonder.name,
          status: wonder.status,
          hp: wonder.hp,
          target_hp: wonder.target_hp,
          hp_pct: ((wonder.hp.to_f / wonder.target_hp) * 100).round,
          started_at: wonder.started_at&.iso8601,
          consecration_at: wonder.consecration_at&.iso8601,
          completed_at: wonder.completed_at&.iso8601,
          destroyed_at: wonder.destroyed_at&.iso8601
        }
      end
    end
  end
end
