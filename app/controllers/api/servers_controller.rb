module Api
  class ServersController < Api::BaseController
    def index
      member_ids = Current.player.server_memberships.pluck(:server_id)
      eligible = Server.all.select do |server|
        member_ids.include?(server.id) || server.admits?(Current.player.email)
      end

      render json: { servers: eligible.map { |s| serialize(s, member_ids.include?(s.id)) } }
    end

    def join
      server = Server.find(params[:id])

      unless server.admits?(Current.player.email)
        return render_error(code: "forbidden", message: "You are not admitted to this server", status: :forbidden)
      end

      membership = ServerMembership.find_or_create_by!(server: server, player: Current.player)
      render json: { membership_id: membership.id, server: serialize(server, true) }, status: :created
    end

    private

    def serialize(server, member)
      {
        id: server.id,
        slug: server.slug,
        name: server.name,
        member: member
      }
    end
  end
end
