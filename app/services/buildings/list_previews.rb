module Buildings
  class ListPreviews
    def self.call(kingdom:)
      new(kingdom: kingdom).call
    end

    def initialize(kingdom:)
      @kingdom = kingdom
    end

    def call
      buildings_by_kind = @kingdom.buildings.index_by(&:kind)
      orders_by_building_id = @kingdom.build_orders.in_progress.includes(:building).index_by(&:building_id)

      Catalog::KINDS.sort.map do |kind|
        preview = UpgradePreview.call(kingdom: @kingdom, kind: kind)
        building = buildings_by_kind[kind]
        order = building && orders_by_building_id[building.id]

        preview.merge(
          id: building&.id,
          upgrade_possible: upgrade_possible?(preview, order),
          build_order: order && Api::KingdomsController.serialize_build_order(order)
        )
      end
    end

    private

    def upgrade_possible?(preview, order)
      return false if order
      return false if preview[:at_max_level]
      return false unless preview[:tier_gates_met]
      return false unless preview[:affordable]
      true
    end
  end
end
