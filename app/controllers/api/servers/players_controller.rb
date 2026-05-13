module Api
  module Servers
    class PlayersController < Api::BaseController
      def show
        membership = ServerMembership.find_by(server_id: params[:server_id], player: Current.player)
        return render_error(code: "forbidden", message: "You are not a member of this server", status: :forbidden) unless membership

        profile = membership.server.player_profiles.find_by(handle: params[:handle])
        return render_error(code: "not_found", message: "Player not found", status: :not_found) unless profile

        render json: serialize(profile)
      end

      private

      def serialize(profile)
        {
          handle: profile.handle,
          real_name: profile.real_name,
          stats: profile.stats,
          joined_at: profile.created_at.iso8601
        }
      end
    end
  end
end
