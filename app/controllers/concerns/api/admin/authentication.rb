module Api
  module Admin
    module Authentication
      extend ActiveSupport::Concern

      private

      def require_admin
        token = bearer_token
        return unauthorized! if token.blank?

        api_key, admin = ApiKey.authenticate(token, owner_type: "Admin")
        return unauthorized! unless api_key && admin

        Current.admin = admin
        Current.api_key = api_key
      end
    end
  end
end
