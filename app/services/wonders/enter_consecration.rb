module Wonders
  # Scheduled-event handler at started_at + 90h. Transitions a fully-built
  # Wonder from `construction` to `consecration`, deducts the 5% payment, and
  # schedules the +24h Complete event. If the Wonder isn't ready (HP < 10000
  # or unpaid milestones or insufficient resources), re-schedules itself.
  class EnterConsecration
    CONSECRATION_DURATION = 24.hours

    def self.call(wonder:)
      new(wonder: wonder).call
    end

    def initialize(wonder:)
      @wonder = wonder
    end

    def call
      ActiveRecord::Base.transaction do
        wonder = Wonder.lock.find(@wonder.id)
        return wonder unless wonder.status == "construction"

        Wonders::ApplyConstruction.call(wonder: wonder)
        wonder.reload

        unless ready_to_consecrate?(wonder)
          re_schedule(wonder, 1.hour)
          return wonder
        end

        begin
          deltas = Wonders::Catalog.consecration_cost.transform_values { |amount| -amount }
          Stockpile::Apply.call(kingdom: wonder.kingdom, deltas: deltas)
        rescue Stockpile::Apply::InsufficientResources
          re_schedule(wonder, 30.minutes)
          return wonder
        end

        now = Time.current
        wonder.update!(status: "consecration", consecration_at: now)

        ScheduledEvents::Schedule.call(
          world: wonder.kingdom.world,
          kind: "wonder_phase",
          fire_at: now + CONSECRATION_DURATION,
          payload: { "wonder_id" => wonder.id, "transition" => "complete" }
        )

        ActiveSupport::Notifications.instrument(
          "dun.wonder.entered_consecration",
          world_id: wonder.kingdom.world_id,
          wonder_id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          consecration_ends_at: now + CONSECRATION_DURATION
        )

        wonder
      end
    end

    private

    def ready_to_consecrate?(wonder)
      wonder.hp >= Wonder::TARGET_HP &&
        wonder.pending_milestone_percent.nil? &&
        wonder.milestones_paid_for?(25) &&
        wonder.milestones_paid_for?(50) &&
        wonder.milestones_paid_for?(75)
    end

    def re_schedule(wonder, delay)
      ScheduledEvents::Schedule.call(
        world: wonder.kingdom.world,
        kind: "wonder_phase",
        fire_at: Time.current + delay,
        payload: { "wonder_id" => wonder.id, "transition" => "enter_consecration" }
      )
    end
  end
end
