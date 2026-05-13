module Api
  module Admin
    module Servers
      class MembersController < Api::Admin::BaseController
        def index
          memberships = server.server_memberships.includes(:player).order(:joined_at)
          render json: { members: memberships.map { |m| serialize(m) } }
        end

        private

        def server
          @server ||= Current.admin.server_adminships.find_by!(server_id: params[:server_id]).server
        end

        def serialize(membership)
          player = membership.player
          {
            membership_id: membership.id,
            player: { id: player.id, email: player.email, name: player.name },
            joined_at: membership.joined_at.iso8601
          }
        end
      end
    end
  end
end
