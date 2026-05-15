module Units
  class TrainingTimeFor
    SPEED_DISCOUNT_PER_LEVEL = 0.05

    def self.call(unit:, building_level:)
      base = Units::Catalog.base_train_time_for(unit)
      level = [building_level.to_i, 1].max
      raw = base * ((1.0 - SPEED_DISCOUNT_PER_LEVEL)**(level - 1))
      raw.round.seconds
    end
  end
end
