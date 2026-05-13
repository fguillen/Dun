module Api
  module Admin
    module Servers
      class InvitationsController < Api::Admin::BaseController
        def index
          accesses = server.server_accesses.where(kind: "invite").order(:value)
          render json: { invitations: accesses.map { |a| serialize(a) } }
        end

        def create
          email = params.require(:email)
          access = ServerInvitations::Create.call(server: server, email: email)
          render json: serialize(access), status: :created
        end

        def destroy
          access = server.server_accesses.where(kind: "invite").find(params[:id])
          access.destroy!
          head :no_content
        end

        private

        def server
          @server ||= Current.admin.server_adminships.find_by!(server_id: params[:server_id]).server
        end

        def serialize(access)
          { id: access.id, email: access.value, created_at: access.created_at.iso8601 }
        end
      end
    end
  end
end
