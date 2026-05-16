module Wonders
  module Catalog
    NAMES = %w[
      sky_tower
      eternal_citadel
      cathedral_of_ages
      library_of_worlds
      crown_of_kings
      black_spire
    ].freeze

    # §16.2 cost table
    COST_TOTALS = {
      "gold"  => 800_000,
      "wood"  => 600_000,
      "stone" => 2_400_000,
      "iron"  => 800_000
    }.freeze

    FOUNDATION_PERCENT   = 25
    MILESTONE_PERCENT    = 10  # paid at each of 25/50/75%
    CONSECRATION_PERCENT = 5

    PREREQUISITES = {
      "town_hall"      => 10,
      "quarry"         => 10,
      "siege_workshop" => 5
    }.freeze

    NODES_REQUIRED = 3

    def self.name?(value)
      NAMES.include?(value.to_s)
    end

    def self.foundation_cost
      cost_for(FOUNDATION_PERCENT)
    end

    def self.milestone_cost
      cost_for(MILESTONE_PERCENT)
    end

    def self.consecration_cost
      cost_for(CONSECRATION_PERCENT)
    end

    def self.cost_for(percent)
      COST_TOTALS.transform_values { |total| (total * percent / 100.0).round }
    end
  end
end
