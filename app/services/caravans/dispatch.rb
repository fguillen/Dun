module Caravans
  # Sends a caravan from one kingdom to another. The escort_units are split off
  # of the caller-supplied source army and dispatched as a "caravan" march; on
  # arrival, Marches::Arrive routes to Caravans::Arrive which decides between
  # Deliver and Intercept.
  class Dispatch
    class CrossWorld           < StandardError; end
    class SelfTrade            < StandardError; end
    class ReceiverEliminated   < StandardError; end
    class InsufficientCapacity < StandardError; end
    class InvalidPayload       < StandardError; end

    ESCORT_NAME_PREFIX = "Caravan".freeze

    def self.call(sender_kingdom:, receiver_kingdom:, source_army:, payload:, escort_units:)
      new(
        sender_kingdom: sender_kingdom,
        receiver_kingdom: receiver_kingdom,
        source_army: source_army,
        payload: payload,
        escort_units: escort_units
      ).call
    end

    def initialize(sender_kingdom:, receiver_kingdom:, source_army:, payload:, escort_units:)
      @sender_kingdom = sender_kingdom
      @receiver_kingdom = receiver_kingdom
      @source_army = source_army
      @payload = normalize_int_hash(payload)
      @escort_units = normalize_int_hash(escort_units)
    end

    def call
      validate_world!
      validate_self_trade!
      validate_receiver_alive!
      validate_payload!
      validate_capacity!

      ActiveRecord::Base.transaction do
        Stockpile::Apply.call(kingdom: @sender_kingdom, deltas: @payload.transform_values { |v| -v })

        escort_name = next_escort_name(@sender_kingdom)
        split = Armies::Split.call(army: @source_army, units: @escort_units, name: escort_name)
        escort_army = split.fetch(:new)

        march_order = Marches::Dispatch.call(
          army: escort_army,
          target_region: @receiver_kingdom.home_region,
          intent: "caravan"
        )

        caravan = Caravan.create!(
          world: @sender_kingdom.world,
          sender_kingdom: @sender_kingdom,
          receiver_kingdom: @receiver_kingdom,
          origin_region_id: @sender_kingdom.home_region_id,
          destination_region_id: @receiver_kingdom.home_region_id,
          escort_army: escort_army,
          outbound_march_order: march_order,
          payload: @payload,
          escort_units: @escort_units,
          status: "in_transit",
          dispatched_at: march_order.dispatched_at,
          arrives_at: march_order.arrives_at
        )

        TradeLedger::Record.call(caravan: caravan, status: "in_transit")

        ActiveSupport::Notifications.instrument(
          "dun.caravan.dispatched",
          world_id: caravan.world_id,
          caravan_id: caravan.id,
          sender_kingdom_id: caravan.sender_kingdom_id,
          receiver_kingdom_id: caravan.receiver_kingdom_id,
          payload: caravan.payload,
          escort_units: caravan.escort_units,
          arrives_at: caravan.arrives_at
        )

        caravan
      end
    end

    private

    def validate_world!
      if @sender_kingdom.world_id != @receiver_kingdom.world_id
        raise CrossWorld, "sender and receiver must be in the same world"
      end
    end

    def validate_self_trade!
      if @sender_kingdom.id == @receiver_kingdom.id
        raise SelfTrade, "cannot send a caravan to yourself"
      end
    end

    def validate_receiver_alive!
      if @receiver_kingdom.eliminated?
        raise ReceiverEliminated, "receiver kingdom is eliminated"
      end
    end

    def validate_payload!
      raise InvalidPayload, "payload must include at least one resource" if @payload.values.sum.zero?
      @payload.each do |resource, amount|
        unless Kingdom::RESOURCES.include?(resource)
          raise InvalidPayload, "unknown resource #{resource}"
        end
        raise InvalidPayload, "amount for #{resource} must be positive" if amount <= 0
      end
    end

    def validate_capacity!
      capacity = @escort_units.sum { |unit, count| Units::Catalog.capacity_for(unit) * count }
      total_payload = @payload.values.sum
      if total_payload > capacity
        raise InsufficientCapacity, "escort capacity #{capacity} cannot carry payload #{total_payload}"
      end
    end

    def normalize_int_hash(hash)
      (hash || {}).each_with_object({}) { |(k, v), out| out[k.to_s] = v.to_i }.reject { |_, v| v.zero? }
    end

    def next_escort_name(kingdom)
      existing = kingdom.armies.where("name LIKE ?", "#{ESCORT_NAME_PREFIX} %").pluck(:name)
      n = (existing.map { |name| name.split.last.to_i }.max || 0) + 1
      "#{ESCORT_NAME_PREFIX} #{n}"
    end
  end
end
