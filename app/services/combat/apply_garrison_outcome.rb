module Combat
  # Light side-effects for a wilderness/ruin garrison battle: applies the
  # attacker's casualties and updates its position. No loot, no walls, no
  # defender row. Node-transfer / cache-grant effects are caller's job
  # (Nodes::Capture / Ruins::Claim) — they happen only on attacker victory and
  # only after this service returns.
  class ApplyGarrisonOutcome
    ATTACKER_WIN = ApplyOutcome::ATTACKER_WIN

    def self.call(battle:)
      new(battle: battle).call
    end

    def initialize(battle:)
      @battle = battle
    end

    def call
      attacker_participant = @battle.participants.find_by(side: "attacker")
      attacker_army = attacker_participant.army
      Army.lock.find(attacker_army.id).update!(composition: attacker_participant.ending_composition)

      apply_attacker_position(attacker_army)

      ActiveSupport::Notifications.instrument(
        "dun.battle.applied",
        world_id: @battle.world_id,
        battle_id: @battle.id,
        outcome: @battle.outcome,
        loot: @battle.loot
      )

      @battle
    end

    private

    def apply_attacker_position(army)
      army.reload
      if army.empty?
        army.destroy! unless army.garrison?
        return
      end

      if ATTACKER_WIN.include?(@battle.outcome)
        army.update!(status: "home", location_region_id: @battle.region_id)
      else
        army.update!(status: "engaged", location_region_id: @battle.region_id)
      end
    end
  end
end
