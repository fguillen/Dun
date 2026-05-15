module Combat
  # Pure per-round combat simulator. Mutates the given state's compositions
  # and walls, returns a structured log entry. No DB I/O. See §16.3 / §16.10.
  class Round
    # Unit-vs-unit RPS multipliers from §16.3. Catapult-vs-Walls is handled
    # via a separate wall-damage stream (CATAPULT_WALL_DAMAGE), not as a
    # unit multiplier.
    RPS = {
      "knight"  => { "archer"  => 1.5 },
      "pikeman" => { "knight"  => 1.6 },
      "archer"  => { "pikeman" => 1.4 }
    }.freeze

    CATAPULT_WALL_DAMAGE = 120
    VARIANCE_RANGE = (0.92..1.08).freeze

    def self.call(state, round_number:)
      new(state, round_number: round_number).call
    end

    def initialize(state, round_number:)
      @state = state
      @round_number = round_number
    end

    def call
      attacker_before = @state.attacker_composition.dup
      defender_before = @state.defender_aggregate.dup

      attacker_dominant = dominant_unit(defender_before)
      defender_dominant = dominant_unit(attacker_before)

      attacker_atk = total_atk(attacker_before, target_dominant: attacker_dominant, marsh_penalty: true)
      defender_atk = total_atk(defender_before, target_dominant: defender_dominant, marsh_penalty: false)
      attacker_def = total_def(attacker_before)
      defender_def_base = total_def(defender_before)
      defender_def = defender_def_base * defender_def_multiplier

      v_attacker = @state.rng.rand(VARIANCE_RANGE)
      v_defender = @state.rng.rand(VARIANCE_RANGE)

      attacker_damage = [ 0.0, attacker_atk - defender_def * 0.5 ].max * v_attacker
      defender_damage = [ 0.0, defender_atk - attacker_def * 0.5 ].max * v_defender

      defender_losses = distribute_damage(defender_before, attacker_damage)
      attacker_losses = distribute_damage(attacker_before, defender_damage)

      @state.attacker_composition = subtract(attacker_before, attacker_losses)
      @state.defender_aggregate   = subtract(defender_before, defender_losses)

      walls_damage, walls_level_after = apply_wall_damage(attacker_before)

      {
        "round" => @round_number,
        "attacker_atk" => attacker_atk.round(2),
        "attacker_def" => attacker_def.round(2),
        "defender_atk" => defender_atk.round(2),
        "defender_def" => defender_def.round(2),
        "attacker_damage_dealt" => attacker_damage.round(2),
        "defender_damage_dealt" => defender_damage.round(2),
        "attacker_casualties"   => attacker_losses.reject { |_, v| v.zero? },
        "defender_casualties"   => defender_losses.reject { |_, v| v.zero? },
        "walls_damage" => walls_damage,
        "walls_level_after" => walls_level_after
      }
    end

    private

    def dominant_unit(composition)
      composition.reject { |_, c| c.to_i.zero? }.max_by { |_, c| c.to_i }&.first
    end

    def total_atk(composition, target_dominant:, marsh_penalty:)
      atk = composition.sum do |unit, count|
        next 0.0 if count.to_i.zero?
        per_unit = Units::Catalog.atk_for(unit)
        mult = RPS.dig(unit, target_dominant) || 1.0
        per_unit * count.to_i * mult
      end
      atk *= (1.0 + Region::MARSH_ATTACKER_PENALTY) if marsh_penalty && @state.terrain == "marsh"
      atk
    end

    def total_def(composition)
      composition.sum do |unit, count|
        next 0.0 if count.to_i.zero?
        Units::Catalog.def_for(unit) * count.to_i
      end
    end

    def defender_def_multiplier
      home_walls = if @state.is_defender_home
        [ 0.20 + 0.01 * @state.walls_level, 0.40 ].min
      else
        0.0
      end
      terrain = [ Region::TERRAIN_COMBAT_MOD.fetch(@state.terrain, 0.0), Region::TERRAIN_COMBAT_CAP ].min
      1.0 + home_walls + terrain
    end

    def distribute_damage(composition, damage)
      losses = composition.each_with_object({}) { |(u, _), out| out[u] = 0 }
      return losses if damage <= 0

      weights = composition.each_with_object({}) do |(u, c), out|
        next if c.to_i.zero?
        out[u] = c.to_i * (1.0 / Units::Catalog.hp_for(u))
      end
      total = weights.values.sum
      return losses if total.zero?

      composition.each do |u, c|
        next if c.to_i.zero?
        share = damage * (weights[u] / total)
        dead = (share / Units::Catalog.hp_for(u)).floor
        losses[u] = [ dead, c.to_i ].min
      end
      losses
    end

    def subtract(composition, losses)
      composition.each_with_object({}) do |(u, c), out|
        out[u] = c.to_i - losses.fetch(u, 0)
      end
    end

    def apply_wall_damage(attacker_before)
      return [ 0, @state.walls_level ] unless @state.walls_level.to_i > 0
      catapults = attacker_before["catapult"].to_i
      return [ 0, @state.walls_level ] if catapults.zero?

      damage = catapults * CATAPULT_WALL_DAMAGE
      remaining = damage
      while remaining > 0 && @state.walls_level > 0
        if @state.walls_hp > remaining
          @state.walls_hp -= remaining
          remaining = 0
        else
          remaining -= @state.walls_hp
          @state.walls_level -= 1
          @state.walls_hp = @state.walls_level * Building::WALL_HP_PER_LEVEL
        end
      end
      @state.walls_hp = 0 if @state.walls_level.zero?

      [ damage, @state.walls_level ]
    end
  end
end
