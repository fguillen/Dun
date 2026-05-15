module Training
  class Complete
    def self.call(training_order:)
      new(training_order: training_order).call
    end

    def initialize(training_order:)
      @training_order = training_order
    end

    def call
      ActiveRecord::Base.transaction do
        order = TrainingOrder.lock.find(@training_order.id)
        return order if order.resolved?

        kingdom = order.kingdom
        garrison = find_or_create_garrison(kingdom)
        merge_units!(garrison, order.unit, order.count)

        order.update!(completed_at: Time.current)
        mark_scheduled_event_processed(order)

        ActiveSupport::Notifications.instrument(
          "dun.training_order.completed",
          world_id: kingdom.world_id,
          kingdom_id: kingdom.id,
          training_order_id: order.id,
          unit: order.unit,
          count: order.count,
          building_kind: order.building_kind
        )

        order
      end
    end

    private

    def find_or_create_garrison(kingdom)
      existing = kingdom.armies
        .where(name: Army::GARRISON_NAME, location_region_id: kingdom.home_region_id)
        .first
      return existing if existing

      kingdom.armies.create!(
        name: Army::GARRISON_NAME,
        location_region_id: kingdom.home_region_id,
        status: "home",
        composition: {}
      )
    end

    def merge_units!(army, unit, count)
      composition = army.composition.dup
      composition[unit] = composition.fetch(unit, 0).to_i + count
      army.update!(composition: composition)
    end

    def mark_scheduled_event_processed(order)
      event = ScheduledEvent.pending
        .where(kind: "training_completion")
        .where("payload->>'training_order_id' = ?", order.id)
        .first
      event&.update!(processed_at: Time.current)
    end
  end
end
