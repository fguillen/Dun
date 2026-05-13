module Api
  module Admin
    module Worlds
      class InvitationsController < Api::Admin::BaseController
        def index
          invitations = world.world_invitations.order(:email)
          render json: { invitations: invitations.map { |i| serialize(i) } }
        end

        def create
          email = params.require(:email)
          invitation = ::WorldInvitations::Create.call(world: world, by_admin: Current.admin, email: email)
          render json: serialize(invitation), status: :created
        end

        def destroy
          invitation = world.world_invitations.find(params[:id])
          invitation.destroy!
          head :no_content
        end

        private

        def world
          @world ||= World
            .joins(server: :server_adminships)
            .where(server_adminships: { admin_id: Current.admin.id })
            .find(params[:world_id])
        end

        def serialize(invitation)
          {
            id: invitation.id,
            email: invitation.email,
            invited_by_admin_id: invitation.invited_by_admin_id,
            created_at: invitation.created_at.iso8601
          }
        end
      end
    end
  end
end
