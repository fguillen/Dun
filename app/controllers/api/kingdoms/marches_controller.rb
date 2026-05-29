module Api
  module Kingdoms
    class MarchesController < Api::BaseController
      def preview
        kingdom = load_kingdom

        ::Marches::ResolveArrivals.call(kingdom)
        kingdom.reload

        render json: ::Marches::BulkPreview.call(kingdom: kingdom)
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
