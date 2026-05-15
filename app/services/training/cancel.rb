module Training
  class Cancel
    class AlreadyResolved < StandardError; end

    REFUND_RATIO = 0.75

    def self.call(training_order:)
      new(training_order: training_order).call
    end

    def initialize(training_order:)
      @training_order = training_order
    end

    def call
      ActiveRecord::Base.transaction do
        order = TrainingOrder.lock.find(@training_order.id)
        raise AlreadyResolved, "training order already resolved" if order.resolved?

        per_unit_cost = Units::Catalog.cost_for(order.unit)
        refund = per_unit_cost.transform_values { |amount| (amount * order.count * REFUND_RATIO).floor }
        Stockpile::Apply.call(kingdom: order.kingdom, deltas: refund)

        order.update!(cancelled_at: Time.current)
        cancel_scheduled_event(order)

        ActiveSupport::Notifications.instrument(
          "dun.training_order.cancelled",
          world_id: order.kingdom.world_id,
          kingdom_id: order.kingdom_id,
          training_order_id: order.id
        )

        order
      end
    end

    private

    def cancel_scheduled_event(order)
      event = ScheduledEvent.pending
        .where(kind: "training_completion")
        .where("payload->>'training_order_id' = ?", order.id)
        .first
      ScheduledEvents::Cancel.call(event) if event
    end
  end
end
