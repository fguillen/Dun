module Combat
  # Outcome applier for caravan interception battles (escort vs hostile at the
  # caravan's destination region). Mirrors `ApplyOutcome` minus walls + loot:
  # the caravan's cargo is the loot, and is handled separately by
  # `Caravans::Intercept`. Both armies receive composition updates; positions
  # follow normal post-battle rules.
  class ApplyEscortOutcome
    ATTACKER_WIN = ApplyOutcome::ATTACKER_WIN

    def self.call(battle:)
      new(battle: battle).call
    end

    def initialize(battle:)
      @battle = battle
    end

    def call
      attacker_participant = @battle.participants.find_by(side: "attacker")
      defender_participants = @battle.participants.where(side: "defender").includes(:army)

      Army.lock.find(attacker_participant.army_id).update!(composition: attacker_participant.ending_composition)
      defender_participants.each do |dp|
        next if dp.army.nil?
        Army.lock.find(dp.army_id).update!(composition: dp.ending_composition)
      end

      @battle.update!(loot: {})

      apply_attacker_position(attacker_participant.army)
      defender_participants.each { |dp| apply_defender_position(dp.army) }

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

    def apply_defender_position(army)
      return if army.nil?
      army.reload
      if army.empty?
        return if army.garrison?
        army.destroy!
        return
      end
      army.update!(status: "home")
    end
  end
end
