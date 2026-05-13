module Api
  module Admin
    module Auth
      class MagicLinksController < Api::Admin::BaseController
        skip_before_action :require_admin, only: %i[create exchange]

        def create
          email = params.require(:email)
          MagicLinks::Request.call(email: email, scope: "admin")
          head :accepted
        end

        def exchange
          raw_token = params.require(:token)
          result = MagicLinks::Consume.call(raw_token: raw_token, scope: "admin")
          render json: serialize(result), status: :created
        rescue MagicLinks::Consume::InvalidToken, MagicLinks::Consume::ScopeMismatch
          render_error(code: "invalid_token", message: "Magic link is invalid", status: :unauthorized)
        rescue MagicLink::AlreadyConsumed
          render_error(code: "already_consumed", message: "Magic link has already been used", status: :unauthorized)
        rescue MagicLink::Expired
          render_error(code: "expired", message: "Magic link has expired", status: :unauthorized)
        end

        private

        def serialize(result)
          {
            api_key: result.raw_token,
            expires_at: result.api_key.expires_at.iso8601,
            owner: { id: result.owner.id, email: result.owner.email, name: result.owner.name, type: "admin" }
          }
        end
      end
    end
  end
end
