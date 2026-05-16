module Caravans
  # Routes a caravan arrival event between delivery and interception. Called by
  # Marches::Arrive when a march with intent "caravan" arrives. If any
  # third-party kingdom has a non-empty army at the destination region in
  # `home` or `engaged` status, the strongest such army intercepts (ties broken
  # deterministically by army.id). Otherwise the caravan delivers.
  class Arrive
    HOSTILE_STATUSES = %w[home engaged].freeze

    def self.call(caravan:)
      new(caravan: caravan).call
    end

    def initialize(caravan:)
      @caravan = caravan
    end

    def call
      caravan = Caravan.find(@caravan.id)
      return caravan unless caravan.in_transit?

      hostile = find_strongest_hostile(caravan)
      if hostile
        Caravans::Intercept.call(caravan: caravan, attacker_army: hostile)
      else
        Caravans::Deliver.call(caravan: caravan)
      end
    end

    private

    def find_strongest_hostile(caravan)
      candidates = Army
        .where(location_region_id: caravan.destination_region_id, status: HOSTILE_STATUSES)
        .where.not(kingdom_id: [ caravan.sender_kingdom_id, caravan.receiver_kingdom_id ])
        .to_a
        .reject(&:empty?)

      return nil if candidates.empty?

      candidates.min_by { |a| [ -raw_attack(a), a.id ] }
    end

    def raw_attack(army)
      army.composition.sum { |unit, count| Units::Catalog.atk_for(unit) * count.to_i }
    end
  end
end
