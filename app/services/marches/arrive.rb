module Marches
  class Arrive
    def self.call(march_order:)
      new(march_order: march_order).call
    end

    def initialize(march_order:)
      @march_order = march_order
    end

    def call
      ActiveRecord::Base.transaction do
        order = MarchOrder.lock.find(@march_order.id)
        return order if order.resolved?

        army = Army.lock.find(order.army_id)
        target = Region.find(order.target_region_id)

        case order.intent
        when "reinforce"
          handle_reinforce(army, target)
        when "scout"
          handle_scout(army, target)
        when "attack", "capture", "claim_ruin"
          handle_combat_stub(army, target)
        when "caravan"
          handle_caravan_stub(army, target)
        end

        order.update!(arrived_at: Time.current)
        mark_scheduled_event_processed(order)

        ActiveSupport::Notifications.instrument(
          "dun.march_order.arrived",
          world_id: army.kingdom.world_id,
          march_order_id: order.id,
          intent: order.intent
        )

        order
      end
    end

    private

    def handle_reinforce(army, target)
      army.update!(status: "home", location_region_id: target.id)
    end

    # Phase 7 will write a Scout report on arrival; for now the scout returns
    # to a "returning" status at the target so subsequent recall logic can
    # bring it home cleanly.
    def handle_scout(army, target)
      army.update!(status: "returning", location_region_id: target.id)
    end

    # Phase 6 (combat) plugs in here — Combat::Resolve will replace this stub.
    # We park the army at the target as `engaged` so the state is meaningful
    # even before Phase 6 ships.
    def handle_combat_stub(army, target)
      army.update!(status: "engaged", location_region_id: target.id)
    end

    # Phase 8 (caravans) plugs in cargo delivery / interception attribution.
    def handle_caravan_stub(army, target)
      army.update!(status: "home", location_region_id: target.id)
    end

    def mark_scheduled_event_processed(order)
      event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", order.id)
        .first
      event&.update!(processed_at: Time.current)
    end
  end
end
