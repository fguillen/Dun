module Api
  module Kingdoms
    class BattlesController < Api::BaseController
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100

      def index
        kingdom = load_kingdom
        limit = clamp_limit(params[:limit])
        offset = params[:offset].to_i.clamp(0, 1_000_000)

        scope = Battle.involving(kingdom.id).order(ended_at: :desc, id: :desc)
        total = scope.count
        battles = scope.limit(limit).offset(offset)

        render json: {
          battles: battles.map { |b| Api::BattlesController.serialize(b) },
          total_count: total
        }
      end

      private

      def clamp_limit(raw)
        return DEFAULT_LIMIT if raw.blank?
        raw.to_i.clamp(1, MAX_LIMIT)
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
