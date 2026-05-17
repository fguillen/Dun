module Api
  module Kingdoms
    class BuildingsController < Api::BaseController
      def index
        kingdom = load_kingdom

        Buildings::ResolveCompletions.call(kingdom)
        kingdom.reload

        rows = Buildings::ListPreviews.call(kingdom: kingdom)
        rows = rows.select { |row| row[:upgrade_possible] } if truthy?(params[:upgrade_possible])

        render json: { kingdom_id: kingdom.id, buildings: rows }
      end

      private

      def truthy?(value)
        %w[true 1].include?(value.to_s.downcase)
      end

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
