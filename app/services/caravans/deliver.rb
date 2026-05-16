module Caravans
  # Successful caravan arrival. Applies the payload to the receiver's stockpile
  # (Warehouse cap silently clamps excess — same as Ruins::Claim per §16.11),
  # flips the ledger entries to delivered, and schedules a retrace return march
  # for the escort army (intent: caravan_return). Emits dun.caravan.delivered.
  class Deliver
    def self.call(caravan:)
      new(caravan: caravan).call
    end

    def initialize(caravan:)
      @caravan = caravan
    end

    def call
      ActiveRecord::Base.transaction do
        caravan = Caravan.lock.find(@caravan.id)
        return caravan unless caravan.in_transit?

        Stockpile::Apply.call(kingdom: caravan.receiver_kingdom, deltas: caravan.payload)

        now = Time.current
        caravan.update!(status: "delivered", delivered_at: now)

        TradeLedger::Record.call(caravan: caravan, status: "delivered")

        schedule_return(caravan, now)

        ActiveSupport::Notifications.instrument(
          "dun.caravan.delivered",
          world_id: caravan.world_id,
          caravan_id: caravan.id,
          sender_kingdom_id: caravan.sender_kingdom_id,
          receiver_kingdom_id: caravan.receiver_kingdom_id,
          payload: caravan.payload
        )

        caravan
      end
    end

    private

    def schedule_return(caravan, now)
      escort = caravan.escort_army
      return if escort.nil?
      escort = Army.lock.find(escort.id)
      return if escort.empty?

      duration = caravan.arrives_at - caravan.dispatched_at
      outbound = caravan.outbound_march_order

      return_order = MarchOrder.create!(
        army: escort,
        origin_region_id: caravan.destination_region_id,
        target_region_id: caravan.origin_region_id,
        intent: "caravan_return",
        path: outbound.path.reverse,
        dispatched_at: now,
        arrives_at: now + duration
      )

      escort.update!(status: "returning", location_region_id: caravan.destination_region_id)
      caravan.update!(return_march_order: return_order)

      ScheduledEvents::Schedule.call(
        world: caravan.world,
        kind: "march_arrival",
        fire_at: return_order.arrives_at,
        payload: { "march_order_id" => return_order.id }
      )
    end
  end
end
