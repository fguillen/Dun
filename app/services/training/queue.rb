module Training
  class Queue
    class WorldNotBuildable < StandardError; end
    class KingdomEliminated < StandardError; end
    class UnknownUnit < StandardError; end
    class BuildingMissing < StandardError; end
    class UnitNotTrainableHere < StandardError; end

    BUILDABLE_WORLD_STATUSES = %w[grace active].freeze

    def self.call(kingdom:, building_kind:, unit:, count:)
      new(kingdom: kingdom, building_kind: building_kind, unit: unit, count: count).call
    end

    def initialize(kingdom:, building_kind:, unit:, count:)
      @kingdom = kingdom
      @building_kind = building_kind.to_s
      @unit = unit.to_s
      @count = count.to_i
    end

    def call
      ActiveRecord::Base.transaction do
        kingdom = Kingdom.lock.find(@kingdom.id)

        raise UnknownUnit, "unknown unit #{@unit}" unless Units::Catalog.kind?(@unit)
        unless TrainingOrder::BUILDING_KINDS.include?(@building_kind)
          raise BuildingMissing, "#{@building_kind} is not a training building"
        end
        raise WorldNotBuildable, "world status #{kingdom.world.status} not buildable" unless BUILDABLE_WORLD_STATUSES.include?(kingdom.world.status)
        raise KingdomEliminated, "kingdom eliminated" if kingdom.eliminated?
        raise ArgumentError, "count must be positive" if @count <= 0

        Training::ResolveCompletions.call(kingdom)
        kingdom.reload

        building = kingdom.buildings.find_by(kind: @building_kind)
        if building.nil? || building.level <= 0
          raise BuildingMissing, "#{@building_kind} not built"
        end

        allowed = Units::Catalog::TRAINS_AT[@building_kind] || []
        unless allowed.include?(@unit)
          raise UnitNotTrainableHere, "#{@unit} cannot be trained at #{@building_kind}"
        end

        per_unit_cost = Units::Catalog.cost_for(@unit)
        total_cost = per_unit_cost.transform_values { |amount| amount * @count }
        deltas = total_cost.transform_values { |amount| -amount }
        Stockpile::Apply.call(kingdom: kingdom, deltas: deltas)

        per_unit_time = Units::TrainingTimeFor.call(unit: @unit, building_level: building.level)
        total_time = per_unit_time * @count
        now = Time.current
        order = TrainingOrder.create!(
          kingdom: kingdom,
          building: building,
          building_kind: @building_kind,
          unit: @unit,
          count: @count,
          started_at: now,
          completes_at: now + total_time
        )

        ScheduledEvents::Schedule.call(
          world: kingdom.world,
          kind: "training_completion",
          fire_at: order.completes_at,
          payload: { "training_order_id" => order.id }
        )

        ActiveSupport::Notifications.instrument(
          "dun.training_order.queued",
          world_id: kingdom.world_id,
          kingdom_id: kingdom.id,
          training_order_id: order.id,
          unit: @unit,
          count: @count,
          building_kind: @building_kind
        )

        order
      end
    end
  end
end
