module Api
  module Admin
    module Servers
      class WorldsController < Api::Admin::BaseController
        def index
          worlds = server.worlds.order(t0_at: :desc)
          render json: { worlds: worlds.map { |w| serialize(w) } }
        end

        def create
          world = ::Worlds::Propose.call(
            server: server,
            organizer_admin: Current.admin,
            name: params.require(:name),
            min_players: params.require(:min_players),
            t0_at: parse_t0_at,
            slug: params[:slug],
            auto_cancel_after_hours: params[:auto_cancel_after_hours]
          )
          render json: serialize(world), status: :created
        rescue ::Worlds::Propose::ConcurrentWorldLimitReached => e
          render_error(code: "concurrent_world_limit_reached", message: e.message, status: :unprocessable_entity)
        end

        private

        def server
          @server ||= Current.admin.server_adminships.find_by!(server_id: params[:server_id]).server
        end

        def parse_t0_at
          raw = params.require(:t0_at)
          Time.iso8601(raw.to_s)
        rescue ArgumentError => e
          raise ActionController::ParameterMissing.new("t0_at: #{e.message}")
        end

        def serialize(world)
          ::Api::Admin::WorldsController.serialize(world)
        end
      end
    end
  end
end
