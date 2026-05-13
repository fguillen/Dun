module Api
  module Admin
    class ServersController < Api::Admin::BaseController
      def index
        servers = Current.admin.server_adminships.includes(:server).map(&:server)
        render json: { servers: servers.map { |s| serialize(s) } }
      end

      def create
        name = params.require(:name)
        slug = params[:slug]
        server = ::Servers::Create.call(owner_admin: Current.admin, name: name, slug: slug)
        render json: serialize(server), status: :created
      end

      def update
        server = administered_server
        ::Servers::Configure.call(server, server_params)
        render json: serialize(server.reload)
      end

      private

      def administered_server
        Current.admin.server_adminships.find_by!(server_id: params[:id]).server
      end

      def server_params
        params.permit(:name, :max_concurrent_worlds, :max_worlds_per_account)
      end

      def serialize(server)
        {
          id: server.id,
          slug: server.slug,
          name: server.name,
          max_concurrent_worlds: server.max_concurrent_worlds,
          max_worlds_per_account: server.max_worlds_per_account,
          owner_admin_id: server.owner_admin_id
        }
      end
    end
  end
end
