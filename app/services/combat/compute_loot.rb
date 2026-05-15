module Combat
  # Pure computation. Returns the raw cap on each resource — whichever is
  # lower of (25% of defender's stockpile) and (attacker's share of capacity).
  # Capacity is divided evenly across the 4 resources, per the Phase 6 plan.
  class ComputeLoot
    PER_RESOURCE_FRACTION = 0.25

    def self.call(defender_kingdom:, attacker_composition:)
      new(defender_kingdom: defender_kingdom, attacker_composition: attacker_composition).call
    end

    def initialize(defender_kingdom:, attacker_composition:)
      @defender_kingdom = defender_kingdom
      @attacker_composition = attacker_composition
    end

    def call
      total_capacity = capacity_for(@attacker_composition)
      per_resource_cap = (total_capacity / Kingdom::RESOURCES.size.to_f).floor

      stockpiles = Stockpile::Read.call(@defender_kingdom)

      Kingdom::RESOURCES.each_with_object({}) do |resource, out|
        twenty_five = (stockpiles[resource].to_i * PER_RESOURCE_FRACTION).floor
        out[resource] = [ twenty_five, per_resource_cap ].min
        out[resource] = 0 if out[resource] < 0
      end
    end

    private

    def capacity_for(composition)
      composition.sum do |unit, count|
        next 0 if count.to_i.zero?
        Units::Catalog.capacity_for(unit) * count.to_i
      end
    end
  end
end
