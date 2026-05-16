module Api
  module Worlds
    class TradeLedgerController < Api::BaseController
      DEFAULT_PAGE_SIZE = 25
      MAX_PAGE_SIZE     = 100

      def index
        world = load_visible_world
        scope = ::TradeLedgerEntry.where(world_id: world.id).newest_first

        if (handle = params[:player]).present?
          scope = scope.for_handle(handle.to_s)
        end

        if (since = parse_since(params[:since]))
          scope = scope.since(since)
        end

        limit = clamp_limit(params[:limit])
        @pagy, entries = pagy(scope, limit: limit)

        render json: {
          entries: entries.map { |e| self.class.serialize(e) },
          pagy: {
            count: @pagy.count,
            page: @pagy.page,
            limit: @pagy.limit,
            pages: @pagy.pages
          }
        }
      end

      def self.serialize(entry)
        {
          id: entry.id,
          caravan_id: entry.caravan_id,
          sender_handle: entry.sender_handle_at_send,
          receiver_handle: entry.receiver_handle_at_send,
          attacker_handle: entry.attacker_handle,
          resource: entry.resource,
          amount: entry.amount,
          status: entry.status,
          recorded_at: entry.recorded_at&.iso8601
        }
      end

      private

      def load_visible_world
        world = ::World.find(params[:world_id])
        profile = ::PlayerProfile.find_by(server_id: world.server_id, player_id: Current.player.id)
        raise ActiveRecord::RecordNotFound, "world not visible" if profile.nil?
        # Server membership grants visibility. (We don't require a kingdom in
        # the world: the ledger is a public per-world record, viewable by any
        # member of the hosting server who could potentially join the world.)
        membership = ::ServerMembership.where(server_id: world.server_id, player_id: Current.player.id).exists?
        raise ActiveRecord::RecordNotFound, "world not visible" unless membership

        world
      end

      def parse_since(raw)
        return nil if raw.blank?
        match = raw.to_s.strip.match(/\A(\d+)\s*([smhdw])?\z/i)
        return nil unless match
        value = match[1].to_i
        unit = (match[2] || "h").downcase
        seconds = case unit
                  when "s" then value
                  when "m" then value * 60
                  when "h" then value * 3_600
                  when "d" then value * 86_400
                  when "w" then value * 604_800
                  end
        seconds ? Time.current - seconds : nil
      end

      def clamp_limit(raw)
        return DEFAULT_PAGE_SIZE if raw.blank?
        n = raw.to_i
        return DEFAULT_PAGE_SIZE if n <= 0
        [ n, MAX_PAGE_SIZE ].min
      end
    end
  end
end
