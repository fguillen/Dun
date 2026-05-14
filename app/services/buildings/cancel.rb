module Buildings
  class Cancel
    class AlreadyResolved < StandardError; end

    REFUND_RATIO = 0.75

    def self.call(build_order:)
      new(build_order: build_order).call
    end

    def initialize(build_order:)
      @build_order = build_order
    end

    def call
      ActiveRecord::Base.transaction do
        order = BuildOrder.lock.find(@build_order.id)
        raise AlreadyResolved, "build order already resolved" if order.resolved?

        cost = Buildings::CostFor.call(kind: order.building.kind, level: order.target_level)
        refund = cost.transform_values { |amount| (amount * REFUND_RATIO).floor }
        Stockpile::Apply.call(kingdom: order.kingdom, deltas: refund)

        order.update!(cancelled_at: Time.current)
        order
      end
    end
  end
end
