module Api
  module Kingdoms
    class BuildOrdersController < Api::BaseController
      def destroy
        kingdom = load_kingdom
        order = kingdom.build_orders.find(params[:id])

        Buildings::Cancel.call(build_order: order)
        order.reload
        render json: Api::KingdomsController.serialize_build_order(order)
      rescue Buildings::Cancel::AlreadyResolved => e
        render_error(code: "build_order_already_resolved", message: e.message, status: :unprocessable_entity)
      end

      def preview
        kingdom = load_kingdom
        kind = params.require(:building).to_s

        Buildings::ResolveCompletions.call(kingdom)
        kingdom.reload

        render json: Buildings::UpgradePreview.call(kingdom: kingdom, kind: kind)
      rescue Buildings::UpgradePreview::UnknownBuilding => e
        render_error(code: "unknown_building", message: e.message, status: :unprocessable_entity)
      end

      private

      def load_kingdom
        kingdom = Kingdom.find(params[:kingdom_id])
        profile = PlayerProfile.find_by(server_id: kingdom.world.server_id, player_id: Current.player.id)
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if profile.nil?
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if kingdom.player_profile_id != profile.id

        kingdom
      end
    end
  end
end
