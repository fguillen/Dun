module Api
  module Kingdoms
    class ArmiesController < Api::BaseController
      def index
        kingdom = load_kingdom
        armies = kingdom.armies.includes(:march_orders).order(:created_at)
        render json: { armies: armies.map { |a| Api::ArmiesController.serialize(a) } }
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
