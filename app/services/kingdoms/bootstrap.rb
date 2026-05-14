module Kingdoms
  class Bootstrap
    STARTER_BUILDINGS = {
      gold_mint: 1, lumber_camp: 1, quarry: 1, iron_mine: 1,
      barracks: 1, walls: 1, watchtower: 1
    }.freeze
    STARTER_LEVY = 20

    def self.call(kingdom, hours_since_t0: 0)
      new(kingdom, hours_since_t0: hours_since_t0).call
    end

    def initialize(kingdom, hours_since_t0:)
      @kingdom = kingdom
      @hours_since_t0 = hours_since_t0.to_i.clamp(0, Float::INFINITY)
    end

    def call
      ActiveRecord::Base.transaction do
        bonus = late_joiner_bonus
        stockpiles = Kingdom::RESOURCES.each_with_object({}) do |r, h|
          h[r] = Kingdom::STARTER_STOCKPILE + bonus
        end
        stockpiles["checkpoint_at"] = Time.current.iso8601

        metadata = (@kingdom.metadata || {}).merge(
          "starter_buildings" => STARTER_BUILDINGS.transform_keys(&:to_s),
          "starter_levy" => STARTER_LEVY,
          "late_joiner_bonus" => bonus,
          "hours_since_t0_at_bootstrap" => @hours_since_t0
        )

        @kingdom.update!(stockpiles: stockpiles, metadata: metadata)
        materialize_buildings
        @kingdom
      end
    end

    private

    def materialize_buildings
      Buildings::Catalog::KINDS.each do |kind|
        starter_level = STARTER_BUILDINGS[kind.to_sym] || 0
        building = @kingdom.buildings.find_or_initialize_by(kind: kind)
        building.level = starter_level if building.new_record?
        building.save!
      end
    end

    def late_joiner_bonus
      raw = (@hours_since_t0 / 12) * Kingdom::LATE_JOINER_BONUS_PER_12H
      [ raw, Kingdom::LATE_JOINER_BONUS_CAP ].min
    end
  end
end
