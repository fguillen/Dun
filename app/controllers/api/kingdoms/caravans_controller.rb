module Api
  module Kingdoms
    class CaravansController < Api::BaseController
      class ReceiverNotFound < StandardError; end

      def create
        kingdom = load_owned_kingdom
        source_army = kingdom.armies.find(params.require(:source_army_id))

        receiver_handle = params.require(:receiver_handle).to_s
        receiver_kingdom = lookup_receiver(kingdom.world, receiver_handle)
        raise ReceiverNotFound, "no kingdom for handle #{receiver_handle}" if receiver_kingdom.nil?

        payload      = stringify_int_hash(params[:payload])
        escort_units = stringify_int_hash(params[:escort_units])

        caravan = ::Caravans::Dispatch.call(
          sender_kingdom: kingdom,
          receiver_kingdom: receiver_kingdom,
          source_army: source_army,
          payload: payload,
          escort_units: escort_units
        )

        render json: self.class.serialize(caravan), status: :created
      rescue ReceiverNotFound => e
        render_error(code: "receiver_not_found", message: e.message, status: :unprocessable_entity)
      rescue ::Caravans::Dispatch::CrossWorld => e
        render_error(code: "cross_world", message: e.message, status: :unprocessable_entity)
      rescue ::Caravans::Dispatch::SelfTrade => e
        render_error(code: "self_trade", message: e.message, status: :unprocessable_entity)
      rescue ::Caravans::Dispatch::ReceiverEliminated => e
        render_error(code: "receiver_eliminated", message: e.message, status: :unprocessable_entity)
      rescue ::Caravans::Dispatch::InsufficientCapacity => e
        render_error(code: "insufficient_capacity", message: e.message, status: :unprocessable_entity)
      rescue ::Caravans::Dispatch::InvalidPayload => e
        render_error(code: "invalid_payload", message: e.message, status: :unprocessable_entity)
      rescue ::Stockpile::Apply::InsufficientResources => e
        render_error(code: "insufficient_resources", message: e.message, status: :unprocessable_entity)
      rescue ::Armies::Split::NotHome => e
        render_error(code: "army_not_home", message: e.message, status: :unprocessable_entity)
      rescue ::Armies::Split::InsufficientUnits => e
        render_error(code: "insufficient_units", message: e.message, status: :unprocessable_entity)
      rescue ::Armies::Split::EmptySplit => e
        render_error(code: "empty_escort", message: e.message, status: :unprocessable_entity)
      rescue ::Marches::Plan::Unreachable => e
        render_error(code: "unreachable", message: e.message, status: :unprocessable_entity)
      end

      def self.serialize(caravan)
        {
          id: caravan.id,
          world_id: caravan.world_id,
          sender_kingdom_id: caravan.sender_kingdom_id,
          receiver_kingdom_id: caravan.receiver_kingdom_id,
          origin_region_id: caravan.origin_region_id,
          destination_region_id: caravan.destination_region_id,
          payload: caravan.payload,
          escort_units: caravan.escort_units,
          status: caravan.status,
          dispatched_at:  caravan.dispatched_at&.iso8601,
          arrives_at:     caravan.arrives_at&.iso8601,
          delivered_at:   caravan.delivered_at&.iso8601,
          intercepted_at: caravan.intercepted_at&.iso8601,
          outbound_march_order_id: caravan.outbound_march_order_id,
          return_march_order_id:   caravan.return_march_order_id
        }
      end

      private

      def load_owned_kingdom
        kingdom = ::Kingdom.find(params[:kingdom_id])
        profile = ::PlayerProfile.find_by(server_id: kingdom.world.server_id, player_id: Current.player.id)
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if profile.nil?
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if kingdom.player_profile_id != profile.id

        kingdom
      end

      def lookup_receiver(world, handle)
        ::Kingdom.joins(player_profile: :player)
          .where(world_id: world.id)
          .where(eliminated_at: nil)
          .find_by("LOWER(player_profiles.handle) = ?", handle.downcase)
      end

      def stringify_int_hash(raw)
        return {} if raw.blank?
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        raw.each_with_object({}) { |(k, v), out| out[k.to_s] = v.to_i }
      end
    end
  end
end
