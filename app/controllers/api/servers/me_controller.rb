module Api
  module Servers
    class MeController < Api::BaseController
      def show
        server_id = params[:id] || params[:server_id]
        profile = PlayerProfile.find_by(server_id: server_id, player: Current.player)

        return render_error(code: "not_found", message: "You have not joined this server", status: :not_found) unless profile
        return render_error(code: "handle_not_set", message: "You haven't set a handle on this server yet.", status: :not_found) if profile.handle.blank?

        render json: serialize_read(profile)
      end

      def update
        server_id = params[:id] || params[:server_id]
        profile = PlayerProfile.find_by!(server_id: server_id, player: Current.player)

        ::Players::SetHandle.call(profile, params[:handle])    if params.key?(:handle)
        ::Players::SetRealName.call(profile, params[:real_name]) if params.key?(:real_name)

        render json: serialize(profile.reload)
      rescue ::Players::HandleLockedError
        render_error(code: "handle_locked", message: "Handle is locked during an active round", status: :unprocessable_entity)
      rescue ActiveRecord::RecordInvalid => e
        render_error(code: "invalid", message: e.record.errors.full_messages.join(", "), status: :unprocessable_entity)
      end

      private

      def serialize(profile)
        {
          handle: profile.handle,
          real_name: profile.real_name,
          stats: profile.stats&.to_counters || {},
          title: ::Titles::Render.call(profile)
        }
      end

      # PlayerProfileRead shape — mirrors Api::Servers::PlayersController#serialize
      # (the showPlayerProfile response), adding joined_at.
      def serialize_read(profile)
        serialize(profile).merge(joined_at: profile.created_at.iso8601)
      end
    end
  end
end
