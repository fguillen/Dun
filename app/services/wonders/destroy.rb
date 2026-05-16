module Wonders
  # Flips a live Wonder to `destroyed`, cancels any pending wonder_phase
  # scheduled events, and emits dun.wonder.destroyed. Paid resources are
  # NOT refunded (per §16.2).
  class Destroy
    def self.call(wonder:, reason: "damage")
      new(wonder: wonder, reason: reason).call
    end

    def initialize(wonder:, reason:)
      @wonder = wonder
      @reason = reason
    end

    def call
      ActiveRecord::Base.transaction do
        wonder = Wonder.lock.find(@wonder.id)
        return wonder if wonder.destroyed_status?

        wonder.update!(
          status: "destroyed",
          destroyed_at: Time.current,
          pending_milestone_percent: nil
        )

        cancel_pending_events(wonder)

        ActiveSupport::Notifications.instrument(
          "dun.wonder.destroyed",
          world_id: wonder.kingdom.world_id,
          wonder_id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          name: wonder.name,
          reason: @reason
        )

        wonder
      end
    end

    private

    def cancel_pending_events(wonder)
      ScheduledEvent
        .pending
        .where(world_id: wonder.kingdom.world_id, kind: "wonder_phase")
        .where("payload ->> 'wonder_id' = ?", wonder.id)
        .each { |event| ScheduledEvents::Cancel.call(event) }
    end
  end
end
