module Api
  module Admin
    module Servers
      class AdminsController < Api::Admin::BaseController
        def index
          adminships = server.server_adminships.includes(:admin).order(:joined_at)
          render json: { admins: adminships.map { |a| serialize(a) } }
        end

        def create
          email = params.require(:email)
          adminship = ::Admins::Invite.call(by_admin: Current.admin, server: server, email: email)
          render json: serialize(adminship), status: :created
        end

        def destroy
          target = ::Admin.find(params[:id])
          ::Admins::RevokeAdminship.call(by_admin: Current.admin, target_admin: target, server: server)
          head :no_content
        rescue ::Admins::LastAdminError
          render_error(code: "last_admin", message: "Cannot remove the only remaining admin", status: :unprocessable_entity)
        end

        private

        def server
          @server ||= Current.admin.server_adminships.find_by!(server_id: params[:server_id]).server
        end

        def serialize(adminship)
          {
            adminship_id: adminship.id,
            admin: { id: adminship.admin.id, email: adminship.admin.email, name: adminship.admin.name },
            role: adminship.role,
            granted_by_admin_id: adminship.granted_by_admin_id,
            joined_at: adminship.joined_at.iso8601
          }
        end
      end
    end
  end
end
