module Api
  module Kingdoms
    class EventsController < Api::BaseController
      DEFAULT_LIMIT = 10
      MAX_LIMIT = 100

      def index
        kingdom = load_kingdom
        events = ::Events::Feed.call(kingdom: kingdom, limit: clamp_limit(params[:limit]))

        render json: { events: events.map { |e| self.class.serialize(e) } }
      end

      def self.serialize(event)
        {
          occurred_at: event.occurred_at&.iso8601,
          type: event.type,
          description: event.description
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
