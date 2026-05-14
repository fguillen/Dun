module Production
  class RateFor
    def self.call(kingdom:, resource:)
      new(kingdom: kingdom, resource: resource).call
    end

    def initialize(kingdom:, resource:)
      @kingdom = kingdom
      @resource = resource.to_s
    end

    def call
      raise ArgumentError, "unknown resource #{@resource}" unless Kingdom::RESOURCES.include?(@resource)

      building_kind = Buildings::Catalog::RESOURCE_BUILDINGS[@resource]
      base_rate = Buildings::Catalog::PRODUCTION_BASE_RATES.fetch(building_kind, 0)
      level = @kingdom.buildings.where(kind: building_kind).pick(:level).to_i

      node_bonus = @kingdom.owned_nodes.where(resource: @resource).sum(:base_rate)

      (base_rate * level) + node_bonus
    end
  end
end
