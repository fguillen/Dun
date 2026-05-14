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

        recalc_in_progress_siblings(order) if building.kind == "stone_mason"

        order
      end
    end

    private

    def recalc_in_progress_siblings(stone_mason_order)
      kingdom = stone_mason_order.kingdom
      kingdom.build_orders.in_progress.where.not(id: stone_mason_order.id).each do |sibling|
        new_time = Buildings::TimeFor.call(
          kind: sibling.building.kind,
          level: sibling.target_level,
          kingdom: kingdom
        )
        sibling.update!(completes_at: sibling.started_at + new_time)
      end
    end
  end
end
