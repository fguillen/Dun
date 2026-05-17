module Training
  class Preview
    class UnknownUnit < StandardError; end
    class InvalidBuildingKind < StandardError; end
    class InvalidCount < StandardError; end

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
      raise UnknownUnit, "unknown unit #{@unit}" unless Units::Catalog.kind?(@unit)
      raise InvalidBuildingKind, "#{@building_kind} is not a training building" unless TrainingOrder::BUILDING_KINDS.include?(@building_kind)
      raise InvalidCount, "count must be positive" if @count <= 0

      building = @kingdom.buildings.find_by(kind: @building_kind)
      building_level = building&.level.to_i
      building_built = building_level >= 1
      unit_trainable_here = Units::Catalog::TRAINS_AT.fetch(@building_kind, []).include?(@unit)

      per_unit_cost = Units::Catalog.cost_for(@unit)
      total_cost = per_unit_cost.transform_values { |amount| amount * @count }

      per_unit_seconds = Units::TrainingTimeFor.call(unit: @unit, building_level: building_level).to_i
      total_seconds = per_unit_seconds * @count

      stockpile = Stockpile::Read.call(@kingdom)
      missing = compute_missing(total_cost, stockpile)
      affordable = missing.values.all?(&:zero?)
      max_affordable_count = compute_max_affordable_count(per_unit_cost, stockpile)

      {
        building_kind: @building_kind,
        unit: @unit,
        count: @count,
        building_level: building_level,
        building_built: building_built,
        unit_trainable_here: unit_trainable_here,
        per_unit_cost: per_unit_cost,
        total_cost: total_cost,
        per_unit_seconds: per_unit_seconds,
        total_seconds: total_seconds,
        affordable: affordable,
        missing: missing,
        max_affordable_count: max_affordable_count
      }
    end

    private

    def compute_missing(total_cost, stockpile)
      Kingdom::RESOURCES.each_with_object({}) do |resource, out|
        out[resource] = [ total_cost[resource].to_i - stockpile[resource].to_i, 0 ].max
      end
    end

    def compute_max_affordable_count(per_unit_cost, stockpile)
      Kingdom::RESOURCES.filter_map do |resource|
        per_unit = per_unit_cost[resource].to_i
        next nil if per_unit <= 0
        stockpile[resource].to_i / per_unit
      end.min || 0
    end
  end
end
