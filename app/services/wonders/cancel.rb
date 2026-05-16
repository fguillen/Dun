module Wonders
  # Player-initiated abandonment. Same effect as destruction — all paid
  # resources are lost (§16.2 "currently full loss"). Build queue unlocks.
  class Cancel
    def self.call(wonder:)
      new(wonder: wonder).call
    end

    def initialize(wonder:)
      @wonder = wonder
    end

    def call
      ActiveRecord::Base.transaction do
        wonder = Wonder.lock.find(@wonder.id)
        return wonder if wonder.destroyed_status? || wonder.completed?

        Wonders::Destroy.call(wonder: wonder, reason: "cancelled")

        ActiveSupport::Notifications.instrument(
          "dun.wonder.cancelled",
          world_id: wonder.kingdom.world_id,
          wonder_id: wonder.id,
          kingdom_id: wonder.kingdom_id
        )

        wonder.reload
      end
    end
  end
end
