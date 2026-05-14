module Buildings
  module Catalog
    KINDS = %w[
      town_hall gold_mint lumber_camp quarry iron_mine warehouse
      barracks stable siege_workshop walls watchtower stone_mason
    ].freeze

    MAX_LEVEL = 20
    COST_GROWTH = 1.75
    TIME_GROWTH = 1.55
    TIME_CAP = 24.hours

    STONE_MASON_DISCOUNT_PER_LEVEL = 0.02
    STONE_MASON_DISCOUNT_MAX = 0.30

    WAREHOUSE_BASE_CAP = 5_000
    WAREHOUSE_LEVEL_COEFF = 2_500

    BASE_COSTS = {
      "town_hall"      => { "gold" => 200, "wood" => 200, "stone" => 200, "iron" => 100 },
      "gold_mint"      => { "gold" => 100, "wood" => 150, "stone" => 50,  "iron" => 0 },
      "lumber_camp"    => { "gold" => 80,  "wood" => 50,  "stone" => 80,  "iron" => 0 },
      "quarry"         => { "gold" => 80,  "wood" => 100, "stone" => 50,  "iron" => 0 },
      "iron_mine"      => { "gold" => 100, "wood" => 100, "stone" => 100, "iron" => 0 },
      "warehouse"      => { "gold" => 50,  "wood" => 200, "stone" => 100, "iron" => 20 },
      "barracks"       => { "gold" => 150, "wood" => 200, "stone" => 100, "iron" => 50 },
      "stable"         => { "gold" => 200, "wood" => 100, "stone" => 50,  "iron" => 150 },
      "siege_workshop" => { "gold" => 300, "wood" => 400, "stone" => 200, "iron" => 200 },
      "walls"          => { "gold" => 100, "wood" => 50,  "stone" => 300, "iron" => 50 },
      "watchtower"     => { "gold" => 100, "wood" => 100, "stone" => 200, "iron" => 30 },
      "stone_mason"    => { "gold" => 200, "wood" => 100, "stone" => 400, "iron" => 100 }
    }.freeze

    # Base times in seconds
    BASE_TIMES = {
      "town_hall"      => 5 * 60,
      "gold_mint"      => 2 * 60,
      "lumber_camp"    => 2 * 60,
      "quarry"         => 2 * 60,
      "iron_mine"      => 3 * 60,
      "warehouse"      => 3 * 60,
      "barracks"       => 5 * 60,
      "stable"         => 8 * 60,
      "siege_workshop" => 15 * 60,
      "walls"          => 8 * 60,
      "watchtower"     => 6 * 60,
      "stone_mason"    => 10 * 60
    }.freeze

    PRODUCTION_BASE_RATES = {
      "gold_mint"   => 30,
      "lumber_camp" => 40,
      "quarry"      => 25,
      "iron_mine"   => 30
    }.freeze

    RESOURCE_BUILDINGS = {
      "gold"  => "gold_mint",
      "wood"  => "lumber_camp",
      "stone" => "quarry",
      "iron"  => "iron_mine"
    }.freeze

    TIER_GATES = {
      "stable"         => { "barracks" => 3 },
      "siege_workshop" => { "barracks" => 5, "iron_mine" => 5 }
    }.freeze

    STARTER_LEVELS = {
      "town_hall"   => 0,
      "gold_mint"   => 1,
      "lumber_camp" => 1,
      "quarry"      => 1,
      "iron_mine"   => 1,
      "warehouse"   => 0,
      "barracks"    => 1,
      "stable"      => 0,
      "siege_workshop" => 0,
      "walls"       => 1,
      "watchtower"  => 1,
      "stone_mason" => 0
    }.freeze

    def self.kind?(kind)
      KINDS.include?(kind.to_s)
    end

    def self.warehouse_cap(level)
      WAREHOUSE_BASE_CAP + WAREHOUSE_LEVEL_COEFF * (level**2)
    end
  end
end
