module Training
  class Catalog
    class InvalidBuildingKind < StandardError; end

    BUILDING_KINDS = TrainingOrder::BUILDING_KINDS

    def self.call(kingdom:, building_kind: nil)
      new(kingdom: kingdom, building_kind: building_kind).call
    end

    def initialize(kingdom:, building_kind: nil)
      @kingdom = kingdom
      @building_kind = building_kind.present? ? building_kind.to_s : nil
    end

    def call
      if @building_kind && !BUILDING_KINDS.include?(@building_kind)
        raise InvalidBuildingKind, "#{@building_kind} is not a training building"
      end

      kinds = @building_kind ? [ @building_kind ] : BUILDING_KINDS

      {
        kingdom_id: @kingdom.id.to_s,
        buildings: kinds.map { |kind| building_entry(kind) }
      }
    end

    private

    def building_entry(kind)
      building       = @kingdom.buildings.find_by(kind: kind)
      building_level = building&.level.to_i
      units          = Units::Catalog::TRAINS_AT.fetch(kind, [])

      {
        building_kind:  kind,
        building_built: building_level >= 1,
        building_level: building_level,
        units: units.map { |unit| unit_entry(kind, unit) }
      }
    end

    def unit_entry(kind, unit)
      preview = Training::Preview.call(
        kingdom: @kingdom, building_kind: kind, unit: unit, count: 1
      )

      {
        unit:                 preview[:unit],
        per_unit_cost:        preview[:per_unit_cost],
        per_unit_seconds:     preview[:per_unit_seconds],
        max_affordable_count: preview[:max_affordable_count],
        trainable:            preview[:building_built] && preview[:unit_trainable_here]
      }
    end
  end
end
