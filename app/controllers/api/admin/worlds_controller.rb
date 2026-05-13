module Api
  module Admin
    class WorldsController < Api::Admin::BaseController
      def show
        render json: self.class.serialize(administered_world)
      end

      def update
        world = administered_world
        ::Worlds::Configure.call(world, world_params)
        render json: self.class.serialize(world.reload)
      rescue ::Worlds::Configure::WorldNotConfigurable => e
        render_error(code: "world_not_configurable", message: e.message, status: :unprocessable_entity)
      end

      def cancel
        world = administered_world
        ::Worlds::Cancel.call(world, by_admin: Current.admin)
        render json: self.class.serialize(world.reload)
      rescue ::Worlds::Cancel::WorldNotCancellable => e
        render_error(code: "world_not_cancellable", message: e.message, status: :unprocessable_entity)
      end

      def self.serialize(world)
        {
          id: world.id,
          server_id: world.server_id,
          name: world.name,
          slug: world.slug,
          seed: world.seed,
          status: world.status,
          min_players: world.min_players,
          auto_cancel_after_hours: world.auto_cancel_after_hours,
          t0_at: world.t0_at&.iso8601,
          grace_closes_at: world.grace_closes_at&.iso8601,
          archived_at: world.archived_at&.iso8601,
          cancelled_at: world.cancelled_at&.iso8601,
          wonder_name: world.wonder_name
        }
      end

      private

      def administered_world
        @administered_world ||= World
          .joins(server: :server_adminships)
          .where(server_adminships: { admin_id: Current.admin.id })
          .find(params[:id])
      end

      def world_params
        permitted = params.permit(:name, :min_players, :t0_at, :auto_cancel_after_hours).to_h
        permitted[:t0_at] = Time.iso8601(permitted[:t0_at]) if permitted[:t0_at].present?
        permitted
      rescue ArgumentError => e
        raise ActionController::ParameterMissing.new("t0_at: #{e.message}")
      end
    end
  end
end
