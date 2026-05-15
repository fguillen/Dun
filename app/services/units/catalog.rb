module Units
  module Catalog
    KINDS = %w[
      levy archer pikeman knight catapult royal_guard scout trebuchet
    ].freeze

    TERRAIN_IMMUNE = %w[knight scout].freeze

    TRAINS_AT = {
      "barracks"       => %w[levy archer pikeman],
      "stable"         => %w[knight scout royal_guard],
      "siege_workshop" => %w[catapult trebuchet]
    }.freeze

    STATS = {
      "levy"        => { atk: 4,  def: 6,  hp: 10, speed: 0.5,  capacity: 50,  cost: { "gold" => 20,   "wood" => 30,   "stone" => 0,    "iron" => 10 },   base_train_time: 45 },
      "archer"      => { atk: 12, def: 4,  hp: 8,  speed: 0.5,  capacity: 30,  cost: { "gold" => 30,   "wood" => 60,   "stone" => 0,    "iron" => 20 },   base_train_time: 90 },
      "pikeman"     => { atk: 8,  def: 18, hp: 16, speed: 0.4,  capacity: 40,  cost: { "gold" => 40,   "wood" => 50,   "stone" => 10,   "iron" => 40 },   base_train_time: 180 },
      "knight"      => { atk: 25, def: 12, hp: 20, speed: 1.0,  capacity: 80,  cost: { "gold" => 100,  "wood" => 20,   "stone" => 0,    "iron" => 80 },   base_train_time: 240 },
      "catapult"    => { atk: 40, def: 8,  hp: 30, speed: 0.25, capacity: 200, cost: { "gold" => 150,  "wood" => 300,  "stone" => 200,  "iron" => 150 },  base_train_time: 1200 },
      "royal_guard" => { atk: 30, def: 35, hp: 40, speed: 0.5,  capacity: 60,  cost: { "gold" => 200,  "wood" => 50,   "stone" => 50,   "iron" => 150 },  base_train_time: 1500 },
      "scout"       => { atk: 2,  def: 2,  hp: 4,  speed: 2.0,  capacity: 10,  cost: { "gold" => 50,   "wood" => 0,    "stone" => 0,    "iron" => 0 },    base_train_time: 60 },
      "trebuchet"   => { atk: 20, def: 6,  hp: 50, speed: 0.2,  capacity: 250, cost: { "gold" => 1500, "wood" => 2000, "stone" => 8000, "iron" => 4000 }, base_train_time: 2700 }
    }.freeze

    def self.kind?(unit)
      KINDS.include?(unit.to_s)
    end

    def self.stats_for(unit)
      STATS.fetch(unit.to_s)
    end

    def self.atk_for(unit);             stats_for(unit)[:atk]; end
    def self.def_for(unit);             stats_for(unit)[:def]; end
    def self.hp_for(unit);              stats_for(unit)[:hp]; end
    def self.speed_for(unit);           stats_for(unit)[:speed]; end
    def self.capacity_for(unit);        stats_for(unit)[:capacity]; end
    def self.cost_for(unit);            stats_for(unit)[:cost]; end
    def self.base_train_time_for(unit); stats_for(unit)[:base_train_time]; end
  end
end
