module Wonders
  # Scheduled-event handler at consecration_at + 24h. Marks the Wonder
  # completed and hands off to `Rounds::End` for the full round-end flow
  # (archive snapshot, stats, titles, leaderboards).
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

        ActiveSupport::Notifications.instrument(
          "dun.wonder.completed",
          world_id: wonder.kingdom.world_id,
          wonder_id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          name: wonder.name
        )

        Rounds::End.call(
          world: wonder.kingdom.world,
          winning_kingdom: wonder.kingdom,
          wonder_name: wonder.name,
          at: now
        )

        wonder
      end
    end
  end
end
