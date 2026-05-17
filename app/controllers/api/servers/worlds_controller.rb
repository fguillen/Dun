module Api
  module Servers
    class WorldsController < Api::BaseController
      def index
        server = Server.find(params[:server_id])
        unless server.server_memberships.exists?(player_id: Current.player.id)
          raise ActiveRecord::RecordNotFound, "server not visible"
        end

        worlds = server.worlds.order(t0_at: :desc)
        render json: { worlds: worlds.map { |w| serialize(w) } }
      end

      private

      def serialize(world)
        {
          id: world.id,
          server_id: world.server_id,
          name: world.name,
          slug: world.slug,
          status: world.status,
          min_players: world.min_players,
          t0_at: world.t0_at&.iso8601,
          grace_closes_at: world.grace_closes_at&.iso8601,
          archived_at: world.archived_at&.iso8601,
          cancelled_at: world.cancelled_at&.iso8601,
          wonder_name: world.wonder_name
        }
      end
    end
  end
end
