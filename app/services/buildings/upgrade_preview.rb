module Buildings
  class UpgradePreview
    class UnknownBuilding < StandardError; end

    def self.call(kingdom:, kind:)
      new(kingdom: kingdom, kind: kind).call
    end

    def initialize(kingdom:, kind:)
      @kingdom = kingdom
      @kind = kind.to_s
    end

    def call
      raise UnknownBuilding, "unknown building #{@kind}" unless Catalog.kind?(@kind)

      building = @kingdom.buildings.find_by(kind: @kind)
      current_level = building&.level.to_i
      at_max = current_level >= Catalog::MAX_LEVEL
      target_level = at_max ? nil : current_level + 1

      tier_gates_unmet = compute_tier_gates_unmet
      cost = at_max ? nil : Buildings::CostFor.call(kind: @kind, level: target_level)
      duration_seconds = at_max ? nil : Buildings::TimeFor.call(kind: @kind, level: target_level, kingdom: @kingdom).to_i
      stockpile = Stockpile::Read.call(@kingdom)
      missing = compute_missing(cost, stockpile)

      {
        kind: @kind,
        current_level: current_level,
        target_level: target_level,
        at_max_level: at_max,
        cost: cost,
        duration_seconds: duration_seconds,
        tier_gates_met: tier_gates_unmet.empty?,
        tier_gates_unmet: tier_gates_unmet,
        affordable: cost.present? && missing.values.all?(&:zero?),
        missing: missing
      }
    end

    private

    def compute_tier_gates_unmet
      gates = Catalog::TIER_GATES[@kind]
      return [] if gates.nil?

      gates.each_with_object([]) do |(required_kind, required_level), out|
        current = @kingdom.buildings.where(kind: required_kind).pick(:level).to_i
        next if current >= required_level
        out << { kind: required_kind, required_level: required_level, current_level: current }
      end
    end

    def compute_missing(cost, stockpile)
      Kingdom::RESOURCES.each_with_object({}) do |resource, out|
        needed = cost ? cost[resource].to_i : 0
        have = stockpile[resource].to_i
        out[resource] = [ needed - have, 0 ].max
      end
    end
  end
end
