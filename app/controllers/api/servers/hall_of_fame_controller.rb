module Api
  module Servers
    class HallOfFameController < Api::BaseController
      def show
        membership = ServerMembership.find_by(server_id: params[:server_id] || params[:id], player: Current.player)
        return render_error(code: "forbidden", message: "You are not a member of this server", status: :forbidden) unless membership

        scope = LeaderboardSnapshot.where(server_id: membership.server_id)
        if params[:kind].present?
          kind = params[:kind].to_s
          return render_error(code: "invalid", message: "unknown kind: #{kind}", status: :unprocessable_entity) unless LeaderboardSnapshot::KINDS.include?(kind)
          scope = scope.where(kind: kind)
        end

        snapshots = scope.index_by(&:kind)

        render json: {
          server_id: membership.server_id,
          leaderboards: LeaderboardSnapshot::KINDS.each_with_object({}) do |kind, h|
            next if params[:kind].present? && params[:kind].to_s != kind
            h[kind] = serialize(snapshots[kind])
          end
        }
      end

      private

      def serialize(snapshot)
        return { snapshot_at: nil, entries: [] } if snapshot.nil?
        {
          snapshot_at: snapshot.snapshot_at.iso8601,
          entries: snapshot.entries.map do |entry|
            profile_id = entry["player_profile_id"]
            profile = profile_id && PlayerProfile.find_by(id: profile_id)
            {
              player_profile_id: profile_id,
              handle: entry["handle"],
              score: entry["score"],
              secondary: entry["secondary"],
              title: profile ? ::Titles::Render.call(profile) : nil
            }
          end
        }
      end
    end
  end
end
