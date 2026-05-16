module Api
  module Worlds
    class ArchiveController < Api::BaseController
      def show
        world = load_visible_world
        archive = world.round_archive
        return render_error(code: "not_found", message: "world is not archived", status: :not_found) if archive.nil?

        render json: {
          world_id: world.id,
          winner_kingdom_id: archive.winner_kingdom_id,
          wonder_name: archive.wonder_name,
          ended_at: archive.ended_at.iso8601,
          frozen_state: archive.frozen_state
        }
      end

      private

      def load_visible_world
        world = ::World.find(params[:world_id])
        membership = ::ServerMembership.where(server_id: world.server_id, player_id: Current.player.id).exists?
        raise ActiveRecord::RecordNotFound, "world not visible" unless membership
        world
      end
    end
  end
end
