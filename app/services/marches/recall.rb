module Marches
  class Recall
    class AlreadyResolved < StandardError; end

    def self.call(march_order:)
      new(march_order: march_order).call
    end

    def initialize(march_order:)
      @march_order = march_order
    end

    def call
      ActiveRecord::Base.transaction do
        order = MarchOrder.lock.find(@march_order.id)
        raise AlreadyResolved, "march order already resolved" if order.resolved?

        cancel_pending_arrival(order)

        now = Time.current
        elapsed = now - order.dispatched_at
        return_order = MarchOrder.create!(
          army: order.army,
          origin_region_id: order.target_region_id,
          target_region_id: order.origin_region_id,
          intent: "reinforce",
          path: order.path.reverse,
          dispatched_at: now,
          arrives_at: now + elapsed
        )

        order.update!(recalled_at: now)
        order.army.update!(status: "returning")

        ScheduledEvents::Schedule.call(
          world: order.army.kingdom.world,
          kind: "march_arrival",
          fire_at: return_order.arrives_at,
          payload: { "march_order_id" => return_order.id }
        )

        ActiveSupport::Notifications.instrument(
          "dun.march_order.recalled",
          world_id: order.army.kingdom.world_id,
          march_order_id: order.id,
          return_march_order_id: return_order.id
        )

        return_order
      end
    end

    private

    def cancel_pending_arrival(order)
      event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", order.id)
        .first
      ScheduledEvents::Cancel.call(event) if event
    end
  end
end
