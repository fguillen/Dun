module Combat
  # Persists the side-effects of a resolved battle: updated army compositions,
  # walls building level + hp, loot transfer (capped by both 25% per-resource
  # and the attacker's Warehouse cap), army position/status updates, and the
  # `dun.battle.applied` notification.
  class ApplyOutcome
    ATTACKER_WIN = %w[attacker_victory defender_rout].freeze

    def self.call(battle:, state:, walls_building:)
      new(battle: battle, state: state, walls_building: walls_building).call
    end

    def initialize(battle:, state:, walls_building:)
      @battle = battle
      @state = state
      @walls_building = walls_building
    end

    def call
      update_walls

      attacker_participant = @battle.participants.find_by(side: "attacker")
      defender_participants = @battle.participants.where(side: "defender").includes(:army)

      apply_compositions(attacker_participant, defender_participants)

      transferred = ATTACKER_WIN.include?(@battle.outcome) ? apply_loot(attacker_participant) : {}
      @battle.update!(loot: transferred)

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

    def update_walls
      return unless @walls_building
      return if @walls_building.level == @state.walls_level && @walls_building.wall_hp.to_i == @state.walls_hp.to_i

      @walls_building.update!(level: @state.walls_level, wall_hp: @state.walls_hp)
    end

    def apply_compositions(attacker_participant, defender_participants)
      attacker_army = attacker_participant.army
      Army.lock.find(attacker_army.id).update!(composition: attacker_participant.ending_composition)

      defender_participants.each do |dp|
        next if dp.army.nil?
        Army.lock.find(dp.army_id).update!(composition: dp.ending_composition)
      end
    end

    def apply_loot(attacker_participant)
      attacker_kingdom = @battle.attacker_kingdom
      defender_kingdom = @battle.defender_kingdom

      raw = ComputeLoot.call(
        defender_kingdom: defender_kingdom,
        attacker_composition: attacker_participant.ending_composition
      )
      return {} if raw.values.all?(&:zero?)

      negative = raw.transform_values { |v| -v }
      Stockpile::Apply.call(kingdom: defender_kingdom, deltas: negative)

      before = Stockpile::Read.call(attacker_kingdom)
      Stockpile::Apply.call(kingdom: attacker_kingdom, deltas: raw)
      after = Stockpile::Read.call(attacker_kingdom)

      Kingdom::RESOURCES.each_with_object({}) do |resource, out|
        out[resource] = (after[resource].to_i - before[resource].to_i)
      end
    end

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
