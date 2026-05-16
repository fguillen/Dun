module Caravans
  # Called by Marches::Arrive when a caravan_return march arrives back at the
  # sender's origin region. Merges the escort army's surviving units back into
  # the sender's home army (first available army at the origin region; created
  # if none) and disposes of the escort army record.
  class CompleteReturn
    def self.call(caravan:)
      new(caravan: caravan).call
    end

    def initialize(caravan:)
      @caravan = caravan
    end

    def call
      ActiveRecord::Base.transaction do
        caravan = Caravan.lock.find(@caravan.id)
        escort = caravan.escort_army
        return caravan if escort.nil?

        escort = Army.lock.find(escort.id)
        kingdom = caravan.sender_kingdom

        target = kingdom.armies
          .where(location_region_id: caravan.origin_region_id, status: "home")
          .where.not(id: escort.id)
          .where.not(name: Army::GARRISON_NAME)
          .order(:created_at)
          .first

        if target
          target = Army.lock.find(target.id)
          merged = merge_compositions(target.composition, escort.composition)
          target.update!(composition: merged)
          escort.destroy!
        else
          # No suitable host army at origin — convert the escort into a home
          # army at the origin (under a stable name) so the player still has
          # access to those units.
          new_name = next_home_army_name(kingdom)
          escort.update!(
            name: new_name,
            status: "home",
            location_region_id: caravan.origin_region_id
          )
        end

        caravan.update!(escort_army_id: nil) unless escort.persisted?

        ActiveSupport::Notifications.instrument(
          "dun.caravan.returned",
          world_id: caravan.world_id,
          caravan_id: caravan.id,
          sender_kingdom_id: caravan.sender_kingdom_id
        )

        caravan
      end
    end

    private

    def merge_compositions(a, b)
      keys = (a.keys | b.keys)
      keys.each_with_object({}) do |k, out|
        sum = a.fetch(k, 0).to_i + b.fetch(k, 0).to_i
        out[k.to_s] = sum if sum > 0
      end
    end

    def next_home_army_name(kingdom)
      base = "Returning Caravan"
      taken = kingdom.armies.where("name LIKE ?", "#{base}%").pluck(:name)
      return base unless taken.include?(base)
      i = 2
      i += 1 while taken.include?("#{base} #{i}")
      "#{base} #{i}"
    end
  end
end
