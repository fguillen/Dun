require "test_helper"

module Combat
  class RoundTest < ActiveSupport::TestCase
    def make_state(
      attacker:, defender:,
      terrain: "plains", is_defender_home: true,
      walls_level: 0, walls_hp: nil,
      seed: 42
    )
      State.new(
        attacker_composition: attacker.dup,
        defender_aggregate: defender.dup,
        starting_attacker_composition: attacker.dup,
        starting_defender_aggregate: defender.dup,
        total_starting_hp_attacker: 0,
        total_starting_hp_defender: 0,
        terrain: terrain,
        is_defender_home: is_defender_home,
        walls_level: walls_level,
        walls_hp: walls_hp || walls_level * Building::WALL_HP_PER_LEVEL,
        rng: Random.new(seed),
        log: []
      )
    end

    test "round produces a log entry with all expected keys" do
      state = make_state(
        attacker: { "levy" => 50 },
        defender: { "levy" => 50 }
      )
      entry = Round.call(state, round_number: 1)

      %w[round attacker_atk attacker_def defender_atk defender_def
         attacker_damage_dealt defender_damage_dealt
         attacker_casualties defender_casualties
         walls_damage walls_level_after].each do |key|
        assert entry.key?(key), "missing key #{key} in #{entry.inspect}"
      end
      assert_equal 1, entry["round"]
    end

    test "RPS: Pikemen apply 1.6x vs a Knight-dominant attacker" do
      no_rps = make_state(
        attacker: { "knight" => 0, "levy" => 200 },
        defender: { "pikeman" => 50 }
      )
      no_rps_entry = Round.call(no_rps, round_number: 1)

      rps = make_state(
        attacker: { "knight" => 100 },
        defender: { "pikeman" => 50 }
      )
      rps_entry = Round.call(rps, round_number: 1)
      assert_in_delta 50 * 8 * 1.6, rps_entry["defender_atk"], 0.01
      refute_equal no_rps_entry["defender_atk"], rps_entry["defender_atk"]
    end

    test "marsh penalty reduces attacker Atk by 10% but does not touch defender Atk" do
      plains = make_state(
        attacker: { "knight" => 100 },
        defender: { "pikeman" => 0, "levy" => 50 },
        terrain: "plains"
      )
      marsh = make_state(
        attacker: { "knight" => 100 },
        defender: { "pikeman" => 0, "levy" => 50 },
        terrain: "marsh"
      )
      p = Round.call(plains, round_number: 1)
      m = Round.call(marsh, round_number: 1)
      assert_in_delta p["attacker_atk"] * 0.9, m["attacker_atk"], 0.01
      assert_in_delta p["defender_atk"], m["defender_atk"], 0.01
    end

    test "defender Def stacks home (+20%) + walls (+1%/level) capped at +40%" do
      no_walls = make_state(
        attacker: { "knight" => 1 },
        defender: { "pikeman" => 10 },
        walls_level: 0
      )
      wall_5 = make_state(
        attacker: { "knight" => 1 },
        defender: { "pikeman" => 10 },
        walls_level: 5
      )
      wall_50 = make_state(
        attacker: { "knight" => 1 },
        defender: { "pikeman" => 10 },
        walls_level: 20
      )
      base = 10 * Units::Catalog.def_for("pikeman")
      assert_in_delta base * (1.0 + 0.20),         Round.call(no_walls, round_number: 1)["defender_def"], 0.01
      assert_in_delta base * (1.0 + 0.20 + 0.05),  Round.call(wall_5, round_number: 1)["defender_def"], 0.01
      # 0.20 + 0.20 = 0.40 cap, not 0.40 + 0.20
      assert_in_delta base * (1.0 + 0.40),         Round.call(wall_50, round_number: 1)["defender_def"], 0.01
    end

    test "terrain combat modifier adds to defender Def, capped at +0.25" do
      plains = make_state(
        attacker: { "knight" => 1 },
        defender: { "pikeman" => 10 },
        terrain: "plains"
      )
      mountain = make_state(
        attacker: { "knight" => 1 },
        defender: { "pikeman" => 10 },
        terrain: "mountain"
      )
      base = 10 * Units::Catalog.def_for("pikeman")
      assert_in_delta base * (1.0 + 0.20 + 0.0),  Round.call(plains, round_number: 1)["defender_def"], 0.01
      assert_in_delta base * (1.0 + 0.20 + 0.25), Round.call(mountain, round_number: 1)["defender_def"], 0.01
    end

    test "non-home defender gets no home bonus but still gets terrain" do
      state = make_state(
        attacker: { "knight" => 1 },
        defender: { "pikeman" => 10 },
        terrain: "hills",
        is_defender_home: false
      )
      base = 10 * Units::Catalog.def_for("pikeman")
      assert_in_delta base * (1.0 + 0.0 + 0.15), Round.call(state, round_number: 1)["defender_def"], 0.01
    end

    test "variance is within [0.92, 1.08] of the raw damage formula" do
      state = make_state(
        attacker: { "knight" => 100 },
        defender: { "levy" => 100 },
        is_defender_home: false,  # take home bonus out of the picture
        terrain: "plains"
      )
      entry = Round.call(state, round_number: 1)
      raw = [ 0.0, entry["attacker_atk"] - entry["defender_def"] * 0.5 ].max
      assert_operator entry["attacker_damage_dealt"], :>=, raw * 0.92 - 0.05
      assert_operator entry["attacker_damage_dealt"], :<=, raw * 1.08 + 0.05
    end

    test "deterministic with the same seed" do
      a = make_state(attacker: { "knight" => 100 }, defender: { "pikeman" => 80 }, seed: 1)
      b = make_state(attacker: { "knight" => 100 }, defender: { "pikeman" => 80 }, seed: 1)
      assert_equal Round.call(a, round_number: 1), Round.call(b, round_number: 1)
    end

    test "casualties never exceed the side's count" do
      state = make_state(
        attacker: { "scout" => 1 },
        defender: { "trebuchet" => 50 }
      )
      entry = Round.call(state, round_number: 1)
      assert_operator entry["attacker_casualties"].fetch("scout", 0), :<=, 1
    end

    test "Catapult damage to walls = 120 per Catapult per round" do
      state = make_state(
        attacker: { "catapult" => 10, "knight" => 50 },
        defender: { "pikeman" => 50 },
        walls_level: 5
      )
      entry = Round.call(state, round_number: 1)
      assert_equal 10 * Round::CATAPULT_WALL_DAMAGE, entry["walls_damage"]
      assert_equal 5, state.walls_level  # 1200 damage < 5000 HP, walls stay at level 5
      assert_equal 5 * Building::WALL_HP_PER_LEVEL - 1200, state.walls_hp
    end

    test "Catapult damage cascades across multiple wall levels in one round" do
      state = make_state(
        attacker: { "catapult" => 50 },
        defender: { "pikeman" => 1 },
        walls_level: 5,
        walls_hp: 500   # already low
      )
      Round.call(state, round_number: 1)
      # damage = 50 × 120 = 6000. Eats 500 (level 5 → 4), then 4000 (level 4 → 3), then 1500 into level 3 (3000 cap).
      assert_equal 3, state.walls_level
      assert_equal 1500, state.walls_hp
    end

    test "walls level cannot drop below 0" do
      state = make_state(
        attacker: { "catapult" => 200 },
        defender: { "pikeman" => 1 },
        walls_level: 1
      )
      Round.call(state, round_number: 1)
      assert_equal 0, state.walls_level
      assert_equal 0, state.walls_hp
    end

    test "no Catapults = no wall damage" do
      state = make_state(
        attacker: { "knight" => 50 },
        defender: { "pikeman" => 50 },
        walls_level: 5
      )
      entry = Round.call(state, round_number: 1)
      assert_equal 0, entry["walls_damage"]
      assert_equal 5, state.walls_level
    end

    test "no walls = no wall damage even with Catapults" do
      state = make_state(
        attacker: { "catapult" => 50 },
        defender: { "pikeman" => 50 },
        walls_level: 0
      )
      entry = Round.call(state, round_number: 1)
      assert_equal 0, entry["walls_damage"]
    end

    test "inverse-HP weighting steers damage to chaff (low HP units)" do
      # Big attacker to ensure non-trivial damage gets distributed.
      state = make_state(
        attacker: { "knight" => 500 },
        defender: { "levy" => 100, "royal_guard" => 100 },
        is_defender_home: false,
        terrain: "plains"
      )
      entry = Round.call(state, round_number: 1)
      levy_dead = entry["defender_casualties"].fetch("levy", 0)
      rg_dead   = entry["defender_casualties"].fetch("royal_guard", 0)
      assert_operator levy_dead, :>, rg_dead, "expected levy losses (#{levy_dead}) to exceed royal_guard losses (#{rg_dead})"
    end
  end
end
