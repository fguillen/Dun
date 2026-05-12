module Api
  module Authentication
    extend ActiveSupport::Concern

    private

    def require_player
      token = bearer_token
      return unauthorized! if token.blank?

      api_key, player = ApiKey.authenticate(token, owner_type: "Player")
      return unauthorized! unless api_key && player

      Current.player = player
      Current.api_key = api_key
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      header.sub(/^Bearer\s+/i, "").presence
    end

    def unauthorized!
      render_error(code: "unauthorized", message: "Invalid or missing API key", status: :unauthorized)
    end
  end
end
