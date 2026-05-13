module Api
  module Auth
    class KeysController < Api::BaseController
      def index
        keys = Current.player.api_keys.order(created_at: :desc)
        render json: { keys: keys.map { |k| serialize(k) } }
      end

      def destroy
        key = Current.player.api_keys.find(params[:id])
        ApiKeys::Revoke.call(key)
        head :no_content
      end

      private

      def serialize(key)
        {
          id: key.id,
          name: key.name,
          last_used_at: key.last_used_at&.iso8601,
          expires_at: key.expires_at.iso8601,
          revoked_at: key.revoked_at&.iso8601,
          current: key.id == Current.api_key&.id
        }
      end
    end
  end
end
