module Combat
  # Resolves a wilderness/ruin garrison fight: the attacker fights a static NPC
  # composition stored on a Node or Ruin row. Mirrors `Combat::Resolve` but
  # without a defender kingdom, defender armies, walls, or home bonus. Terrain
  # modifiers (including the marsh attacker penalty) still apply via
  # `Combat::Round`.
  #
  # Persists a Battle row with `defender_kingdom_id: nil` plus an attacker
  # participant and a wilderness defender participant (kingdom_id and army_id
  # both nil). Casualty / position side-effects run through
  # `Combat::ApplyGarrisonOutcome`. The node-transfer or cache-grant happens in
  # `Nodes::Capture` / `Ruins::Claim` *after* this service returns.
  class ResolveGarrison
    MAX_ROUNDS = Resolve::MAX_ROUNDS
    ROUT_THRESHOLD = Resolve::ROUT_THRESHOLD
    ROUT_FLEE_RATE = Resolve::ROUT_FLEE_RATE

    def self.call(march_order:, garrison:, rng: Random.new)
      new(march_order: march_order, garrison: garrison, rng: rng).call
    end

    def initialize(march_order:, garrison:, rng:)
      @march_order = march_order
      @garrison = stringify(garrison)
      @rng = rng
    end

    def call
      ActiveRecord::Base.transaction do
        attacker_army = Army.lock.find(@march_order.army_id)
        region = Region.find(@march_order.target_region_id)

        return nil if attacker_army.empty?
        return nil if @garrison.values.map(&:to_i).sum.zero?

        state = build_state(attacker_army, region)
        started_at = Time.current

        outcome = nil
        (1..MAX_ROUNDS).each do |round_number|
          entry = Round.call(state, round_number: round_number)
          state.log << entry

          a_frac = hp_fraction(state.attacker_composition, state.total_starting_hp_attacker)
          d_frac = hp_fraction(state.defender_aggregate, state.total_starting_hp_defender)

          if a_frac < ROUT_THRESHOLD
            apply_rout!(state.attacker_composition)
            outcome = "attacker_rout"
            break
          elsif d_frac < ROUT_THRESHOLD
            apply_rout!(state.defender_aggregate)
            outcome = "defender_rout"
            break
          end
        end
        outcome ||= determine_outcome(state)
        ended_at = Time.current

        battle = Battle.create!(
          world_id: region.world_id,
          region: region,
          attacker_kingdom_id: attacker_army.kingdom_id,
          defender_kingdom_id: nil,
          march_order: @march_order,
          outcome: outcome,
          loot: {},
          log: state.log,
          variance_seed: rng_seed_string,
          started_at: started_at,
          ended_at: ended_at
        )

        BattleParticipant.create!(
          battle: battle,
          kingdom_id: attacker_army.kingdom_id,
          army: attacker_army,
          side: "attacker",
          starting_composition: state.starting_attacker_composition,
          ending_composition: state.attacker_composition,
          casualties: diff_composition(state.starting_attacker_composition, state.attacker_composition)
        )

        BattleParticipant.create!(
          battle: battle,
          kingdom_id: nil,
          army_id: nil,
          side: "defender",
          starting_composition: state.starting_defender_aggregate,
          ending_composition: state.defender_aggregate,
          casualties: diff_composition(state.starting_defender_aggregate, state.defender_aggregate)
        )

        ApplyGarrisonOutcome.call(battle: battle)

        ActiveSupport::Notifications.instrument(
          "dun.garrison.defeated",
          world_id: battle.world_id,
          region_id: battle.region_id,
          battle_id: battle.id,
          attacker_kingdom_id: battle.attacker_kingdom_id,
          outcome: battle.outcome
        )

        battle
      end
    end

    private

    def stringify(garrison)
      (garrison || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_i }
    end

    def build_state(attacker_army, region)
      starting_attacker = attacker_army.composition.dup
      starting_defender = @garrison.dup

      State.new(
        attacker_composition: starting_attacker.dup,
        defender_aggregate: starting_defender.dup,
        starting_attacker_composition: starting_attacker,
        starting_defender_aggregate: starting_defender,
        total_starting_hp_attacker: total_hp(starting_attacker),
        total_starting_hp_defender: total_hp(starting_defender),
        terrain: region.terrain,
        is_defender_home: false,
        walls_level: 0,
        walls_hp: 0,
        rng: @rng,
        log: []
      )
    end

    def total_hp(composition)
      composition.sum do |unit, count|
        next 0 if count.to_i.zero?
        Units::Catalog.hp_for(unit) * count.to_i
      end
    end

    def hp_fraction(composition, starting_hp)
      return 0.0 if starting_hp.to_i.zero?
      total_hp(composition).to_f / starting_hp.to_f
    end

    def apply_rout!(composition)
      composition.each do |unit, count|
        composition[unit] = (count.to_i * (1.0 - ROUT_FLEE_RATE)).floor
      end
    end

    def determine_outcome(state)
      a = total_hp(state.attacker_composition)
      d = total_hp(state.defender_aggregate)
      return "attacker_victory" if a > d
      "defender_victory"
    end

    def diff_composition(before, after)
      keys = before.keys | after.keys
      keys.each_with_object({}) do |unit, out|
        delta = before.fetch(unit, 0).to_i - after.fetch(unit, 0).to_i
        out[unit] = delta if delta != 0
      end
    end

    def rng_seed_string
      @rng.respond_to?(:seed) ? @rng.seed.to_s : nil
    end
  end
end
