module Buildings
  class Complete
    def self.call(build_order:)
      new(build_order: build_order).call
    end

    def initialize(build_order:)
      @build_order = build_order
    end

    def call
      ActiveRecord::Base.transaction do
        order = BuildOrder.lock.find(@build_order.id)
        return order if order.resolved?

        building = Building.lock.find(order.building_id)
        building.update!(level: order.target_level)
        order.update!(completed_at: Time.current)

        mark_scheduled_event_processed(order)
        recalc_in_progress_siblings(order) if building.kind == "stone_mason"

        ActiveSupport::Notifications.instrument(
          "dun.build_order.completed",
          world_id: order.kingdom.world_id,
          kingdom_id: order.kingdom_id,
          build_order_id: order.id,
          building_kind: building.kind,
          level: building.level
        )

        order
      end
    end

    private

    def mark_scheduled_event_processed(order)
      event = ScheduledEvent.pending
        .where(kind: "build_completion")
        .where("payload->>'build_order_id' = ?", order.id)
        .first
      event&.update!(processed_at: Time.current)
    end

    def recalc_in_progress_siblings(stone_mason_order)
      kingdom = stone_mason_order.kingdom
      kingdom.build_orders.in_progress.where.not(id: stone_mason_order.id).each do |sibling|
        new_time = Buildings::TimeFor.call(
          kind: sibling.building.kind,
          level: sibling.target_level,
          kingdom: kingdom
        )
        sibling.update!(completes_at: sibling.started_at + new_time)
        reschedule_sibling_event(sibling)
      end
    end

    def reschedule_sibling_event(sibling)
      event = ScheduledEvent.pending
        .where(kind: "build_completion")
        .where("payload->>'build_order_id' = ?", sibling.id)
        .first
      event&.update!(fire_at: sibling.completes_at)
    end
  end
end
