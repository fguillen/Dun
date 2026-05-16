module Wonders
  # Scheduled-event handler at consecration_at + 24h. Marks the Wonder
  # completed and archives the world (minimal Phase 9 hook — Phase 10's
  # Rounds::End will replace this with the full freeze/snapshot flow).
  class Complete
    def self.call(wonder:)
      new(wonder: wonder).call
    end

    def initialize(wonder:)
      @wonder = wonder
    end

    def call
      ActiveRecord::Base.transaction do
        wonder = Wonder.lock.find(@wonder.id)
        return wonder if wonder.destroyed_status?
        return wonder if wonder.completed?
        return wonder unless wonder.status == "consecration"
        return wonder if wonder.hp <= 0

        now = Time.current
        wonder.update!(status: "completed", completed_at: now)

        world = wonder.kingdom.world
        world.update!(
          status: "archived",
          archived_at: now,
          winner_kingdom_id: wonder.kingdom_id,
          wonder_name: wonder.name
        )

        ActiveSupport::Notifications.instrument(
          "dun.wonder.completed",
          world_id: world.id,
          wonder_id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          name: wonder.name
        )

        ActiveSupport::Notifications.instrument(
          "dun.world.archived",
          world_id: world.id,
          winner_kingdom_id: wonder.kingdom_id,
          wonder_name: wonder.name
        )

        wonder
      end
    end
  end
end
