module Api
  module Worlds
    class KingdomsController < Api::BaseController
      # Public roster of every kingdom in the world: who is playing, how many,
      # and coarse progress (territory counts, Wonder, reputation title). Detailed
      # intel — stockpiles, buildings, armies, queues — stays scout-only (§16.9).
      def index
        kingdoms = world.kingdoms.includes(:player_profile, :home_region).order(:joined_at)
        ids = kingdoms.map(&:id)

        node_counts = Node.where(owner_kingdom_id: ids).group(:owner_kingdom_id).count
        ruin_counts = Ruin.where(claimed_by_kingdom_id: ids).group(:claimed_by_kingdom_id).count
        wonders = wonders_by_kingdom
        my_profile_id = PlayerProfile.where(server_id: world.server_id, player_id: Current.player.id).pick(:id)

        render json: {
          kingdoms: kingdoms.map { |k| serialize(k, node_counts, ruin_counts, wonders, my_profile_id) }
        }
      end

      private

      def world
        @world ||= begin
          w = World.find(params[:world_id])
          raise ActiveRecord::RecordNotFound, "world not visible" unless w.server.server_memberships.exists?(player_id: Current.player.id)
          w
        end
      end

      # One Wonder per kingdom: prefer a live Wonder, otherwise the most recent.
      def wonders_by_kingdom
        ::Wonder
          .joins(:kingdom)
          .where(kingdoms: { world_id: world.id })
          .order(:created_at)
          .each_with_object({}) do |wonder, map|
            existing = map[wonder.kingdom_id]
            map[wonder.kingdom_id] = wonder if existing.nil? || wonder.live? || !existing.live?
          end
      end

      def serialize(kingdom, node_counts, ruin_counts, wonders, my_profile_id)
        wonder = wonders[kingdom.id]
        {
          kingdom_id: kingdom.id,
          handle: kingdom.handle,
          title: ::Titles::Render.call(kingdom.player_profile),
          is_you: kingdom.player_profile_id == my_profile_id,
          home_region_id: kingdom.home_region_id,
          home_region_name: kingdom.home_region&.name,
          nodes_controlled: node_counts[kingdom.id].to_i,
          ruins_claimed: ruin_counts[kingdom.id].to_i,
          wonder: wonder && serialize_wonder(wonder),
          eliminated: kingdom.eliminated?,
          joined_at: kingdom.joined_at&.iso8601
        }
      end

      def serialize_wonder(wonder)
        {
          name: wonder.name,
          status: wonder.status,
          hp_pct: ((wonder.hp.to_f / wonder.target_hp) * 100).round
        }
      end
    end
  end
end
