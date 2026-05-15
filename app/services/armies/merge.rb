module Armies
  class Merge
    class IncompatibleKingdom < StandardError; end
    class IncompatibleLocation < StandardError; end
    class IncompatibleStatus < StandardError; end

    def self.call(into:, from:)
      new(into: into, from: from).call
    end

    def initialize(into:, from:)
      @into = into
      @from = from
    end

    def call
      raise ArgumentError, "cannot merge an army into itself" if @into.id == @from.id

      ActiveRecord::Base.transaction do
        ids = [ @into.id, @from.id ].sort
        locked = Army.lock.where(id: ids).to_a.index_by(&:id)
        into = locked[@into.id]
        from = locked[@from.id]

        raise IncompatibleKingdom, "armies must be in the same kingdom" if into.kingdom_id != from.kingdom_id
        raise IncompatibleLocation, "armies must be in the same region" if into.location_region_id != from.location_region_id
        raise IncompatibleStatus, "both armies must be home to merge" unless into.status == "home" && from.status == "home"

        merged = into.composition.dup
        from.composition.each do |unit, count|
          merged[unit] = merged.fetch(unit, 0).to_i + count.to_i
        end
        into.update!(composition: merged)
        from.destroy!

        ActiveSupport::Notifications.instrument(
          "dun.army.merged",
          world_id: into.kingdom.world_id,
          kingdom_id: into.kingdom_id,
          into_army_id: into.id,
          from_army_id: from.id
        )

        into
      end
    end
  end
end
