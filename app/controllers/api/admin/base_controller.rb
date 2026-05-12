module Api
  module Admin
    class BaseController < Api::BaseController
      include Api::Admin::Authentication

      skip_before_action :require_player
      before_action :require_admin
    end
  end
end
