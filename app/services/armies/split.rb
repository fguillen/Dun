module Armies
  class Split
    class NotHome < StandardError; end
    class InsufficientUnits < StandardError; end
    class EmptySplit < StandardError; end

    def self.call(army:, units:, name:)
      new(army: army, units: units, name: name).call
    end

    def initialize(army:, units:, name:)
      @army = army
      @units = units
      @name = name
    end

    def call
      ActiveRecord::Base.transaction do
        source = Army.lock.find(@army.id)
        raise NotHome, "army must be home to split" unless source.status == "home"

        units = stringify_units(@units)
        raise EmptySplit, "split must include at least one unit" if units.values.sum.zero?

        composition = source.composition.dup
        units.each do |unit, count|
          available = composition.fetch(unit, 0).to_i
          if count > available
            raise InsufficientUnits, "not enough #{unit} (have #{available}, want #{count})"
          end
          composition[unit] = available - count
        end
        composition.delete_if { |_, c| c.to_i.zero? }

        new_army = source.kingdom.armies.create!(
          name: @name,
          location_region_id: source.location_region_id,
          status: "home",
          composition: units
        )

        if composition.empty? && !source.garrison?
          source.destroy!
          source = nil
        else
          source.update!(composition: composition)
        end

        ActiveSupport::Notifications.instrument(
          "dun.army.split",
          world_id: new_army.kingdom.world_id,
          kingdom_id: new_army.kingdom_id,
          source_army_id: source&.id,
          new_army_id: new_army.id
        )

        { source: source, new: new_army }
      end
    end

    private

    def stringify_units(units)
      units.each_with_object({}) do |(k, v), out|
        out[k.to_s] = v.to_i
      end.reject { |_, v| v.zero? }
    end
  end
end
