module Combat
  # Orchestrates a single PvP battle triggered by an `attack` march arrival.
  # Returns the persisted Battle (with participants) or nil if no defender is
  # present at the target region (caller parks the attacker army `home`).
  class Resolve
    MAX_ROUNDS = 6
    ROUT_THRESHOLD = 0.15
    ROUT_FLEE_RATE = 0.30

    def self.call(march_order:, defender_kingdom: nil, defender_army: nil, rng: Random.new)
      new(march_order: march_order, defender_kingdom: defender_kingdom, defender_army: defender_army, rng: rng).call
    end

    def initialize(march_order:, defender_kingdom: nil, defender_army: nil, rng:)
      @march_order = march_order
      @explicit_defender_kingdom = defender_kingdom
      @explicit_defender_army = defender_army
      @rng = rng
    end

    def call
      ActiveRecord::Base.transaction do
        attacker_army = Army.lock.find(@march_order.army_id)
        region = Region.find(@march_order.target_region_id)

        if @explicit_defender_army
          defender_armies = [ Army.lock.find(@explicit_defender_army.id) ].reject(&:empty?)
          return nil if defender_armies.empty?
          defender_kingdom = defender_armies.first.kingdom
        else
          defender_kingdom = @explicit_defender_kingdom || find_defender_kingdom(region, attacker_army.kingdom_id)
          return nil if defender_kingdom.nil?

          defender_armies = defender_kingdom.armies
            .where(location_region_id: region.id, status: %w[home engaged])
            .lock
            .to_a
          return nil if defender_armies.empty? || defender_armies.all?(&:empty?)

          defender_armies.reject!(&:empty?)
        end

        defender_aggregate = aggregate_compositions(defender_armies)
        return nil if defender_aggregate.values.all?(&:zero?)

        walls_building = nil
        walls_level = 0
        walls_hp = 0
        # An escort defending its caravan is in the open: no walls, no home bonus.
        # Only apply walls/home when the defender is genuinely the home kingdom
        # of this region (the normal PvP arrival case).
        is_home = @explicit_defender_army.nil? && region.id == defender_kingdom.home_region_id
        if is_home
          walls_building = defender_kingdom.buildings.find_by(kind: "walls")
          if walls_building && walls_building.level > 0
            walls_level = walls_building.level
            walls_hp = walls_building.current_wall_hp
          end
        end

        state = build_state(attacker_army, defender_aggregate, region, is_home, walls_level, walls_hp)
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

        defender_endings = redistribute(defender_armies, state.defender_aggregate)
        ended_at = Time.current

        battle = Battle.create!(
          world_id: region.world_id,
          region: region,
          attacker_kingdom_id: attacker_army.kingdom_id,
          defender_kingdom_id: defender_kingdom.id,
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

        defender_armies.each do |darmy|
          BattleParticipant.create!(
            battle: battle,
            kingdom: defender_kingdom,
            army: darmy,
            side: "defender",
            starting_composition: darmy.composition.dup,
            ending_composition: defender_endings.fetch(darmy.id),
            casualties: diff_composition(darmy.composition, defender_endings.fetch(darmy.id))
          )
        end

        if @explicit_defender_army
          ApplyEscortOutcome.call(battle: battle)
        else
          ApplyOutcome.call(battle: battle, state: state, walls_building: walls_building)
          apply_wonder_damage(battle, state, defender_kingdom, region, attacker_army)
        end

        ActiveSupport::Notifications.instrument(
          "dun.battle.resolved",
          world_id: battle.world_id,
          region_id: battle.region_id,
          battle_id: battle.id,
          attacker_kingdom_id: battle.attacker_kingdom_id,
          defender_kingdom_id: battle.defender_kingdom_id,
          outcome: battle.outcome
        )

        battle
      end
    end

    private

    def find_defender_kingdom(region, attacker_kingdom_id)
      Kingdom.where(world_id: region.world_id, home_region_id: region.id)
        .where.not(id: attacker_kingdom_id)
        .first
    end

    def aggregate_compositions(armies)
      armies.each_with_object(Hash.new(0)) do |army, agg|
        army.composition.each { |unit, count| agg[unit] += count.to_i }
      end.to_h
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
      "defender_victory"   # ties go to the defender
    end

    def diff_composition(before, after)
      keys = before.keys | after.keys
      keys.each_with_object({}) do |unit, out|
        delta = before.fetch(unit, 0).to_i - after.fetch(unit, 0).to_i
        out[unit] = delta if delta != 0
      end
    end

    # Distribute aggregate casualties back across the contributing armies.
    # Strategy: largest contributor per unit kind absorbs losses first.
    # Deterministic by (count desc, army.id asc).
    def redistribute(armies, ending_aggregate)
      starting_per_army = armies.each_with_object({}) do |a, h|
        h[a.id] = a.composition.dup
      end

      starting_aggregate = Hash.new(0)
      starting_per_army.each_value { |c| c.each { |u, n| starting_aggregate[u] += n.to_i } }

      endings = starting_per_army.transform_values(&:dup)

      starting_aggregate.each do |unit, total|
        casualties = total - ending_aggregate.fetch(unit, 0).to_i
        next if casualties <= 0

        ordered = armies.sort_by { |a| [ -a.composition[unit].to_i, a.id ] }
        ordered.each do |army|
          available = endings.fetch(army.id).fetch(unit, 0).to_i
          take = [ available, casualties ].min
          next if take.zero?
          endings[army.id][unit] = available - take
          casualties -= take
          break if casualties.zero?
        end
      end

      endings
    end

    def build_state(attacker_army, defender_aggregate, region, is_home, walls_level, walls_hp)
      starting_attacker = attacker_army.composition.dup
      starting_defender = defender_aggregate.dup

      State.new(
        attacker_composition: starting_attacker.dup,
        defender_aggregate: starting_defender.dup,
        starting_attacker_composition: starting_attacker,
        starting_defender_aggregate: starting_defender,
        total_starting_hp_attacker: total_hp(starting_attacker),
        total_starting_hp_defender: total_hp(starting_defender),
        terrain: region.terrain,
        is_defender_home: is_home,
        walls_level: walls_level,
        walls_hp: walls_hp,
        rng: @rng,
        log: []
      )
    end

    def rng_seed_string
      @rng.respond_to?(:seed) ? @rng.seed.to_s : nil
    end

    ATTACKER_WIN_OUTCOMES = %w[attacker_victory defender_rout].freeze

    def apply_wonder_damage(battle, state, defender_kingdom, region, attacker_army)
      return unless ATTACKER_WIN_OUTCOMES.include?(battle.outcome)
      return unless region.id == defender_kingdom.home_region_id

      wonder = Wonders::LiveFor.call(defender_kingdom)
      return unless wonder

      surviving_trebuchets = state.attacker_composition["trebuchet"].to_i
      return if surviving_trebuchets <= 0

      Wonders::Damage.call(
        wonder: wonder,
        attacker_kingdom: attacker_army.kingdom,
        trebuchets_surviving: surviving_trebuchets,
        battle: battle
      )
    end
  end
end
