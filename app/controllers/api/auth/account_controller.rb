module Api
  module Auth
    class AccountController < Api::BaseController
      def destroy
        ::Accounts::Delete.call(player: Current.player)
        head :no_content
      end
    end
  end
end
