module Wonders
  # Initiates a Wonder: validates prereqs, deducts foundation 25%, creates the
  # Wonder row in `construction` status (foundation is "instant" per §14),
  # schedules the +90h consecration transition, emits dun.wonder.started.
  class Start
    class UnknownName < StandardError; end

    CONSTRUCTION_DURATION = 90.hours

    def self.call(kingdom:, name:)
      new(kingdom: kingdom, name: name.to_s).call
    end

    def initialize(kingdom:, name:)
      @kingdom = kingdom
      @name = name
    end

    def call
      ActiveRecord::Base.transaction do
        raise UnknownName, "unknown wonder name #{@name.inspect}" unless Catalog.name?(@name)

        kingdom = Kingdom.lock.find(@kingdom.id)
        Wonders::Prerequisites.call(kingdom: kingdom)

        deltas = Catalog.foundation_cost.transform_values { |amount| -amount }
        Stockpile::Apply.call(kingdom: kingdom, deltas: deltas)

        now = Time.current
        wonder = Wonder.create!(
          kingdom: kingdom,
          name: @name,
          status: "construction",
          hp: Wonder::FOUNDATION_HP,
          target_hp: Wonder::TARGET_HP,
          started_at: now,
          construction_started_at: now,
          last_construction_at: now,
          milestones_paid: { "25" => false, "50" => false, "75" => false },
          repaired_hp_by_phase: { "foundation" => 0, "construction" => 0, "consecration" => 0 }
        )

        ScheduledEvents::Schedule.call(
          world: kingdom.world,
          kind: "wonder_phase",
          fire_at: now + CONSTRUCTION_DURATION,
          payload: { "wonder_id" => wonder.id, "transition" => "enter_consecration" }
        )

        ActiveSupport::Notifications.instrument(
          "dun.wonder.started",
          world_id: kingdom.world_id,
          wonder_id: wonder.id,
          kingdom_id: kingdom.id,
          name: wonder.name
        )

        wonder
      end
    end
  end
end
