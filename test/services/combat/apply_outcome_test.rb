require "test_helper"

module Combat
  class ApplyOutcomeTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world, terrain: "plains", name: "Battleground")

      @attacker = create(:kingdom, :with_buildings, world: @world, home_region: create(:region, world: @world, name: "AHome"))
      @defender = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @defender.update!(stockpiles: {
        "gold" => 4_000, "wood" => 4_000, "stone" => 4_000, "iron" => 4_000,
        "checkpoint_at" => Time.current.iso8601
      })
      @attacker.update!(stockpiles: {
        "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    def build_battle_with_state(outcome:, attacker_after:, defender_after:, walls_level: 0, walls_hp: 0)
      attacker_army = create(:army, kingdom: @attacker, location_region: @region, name: "Strike",
        composition: { "knight" => 100 })
      defender_army = create(:army, kingdom: @defender, location_region: @region, name: "Volunteers",
        composition: { "pikeman" => 50 })

      battle = Battle.create!(
        world: @world, region: @region,
        attacker_kingdom: @attacker, defender_kingdom: @defender,
        outcome: outcome, loot: {}, log: [], started_at: 2.minutes.ago, ended_at: 1.minute.ago
      )
      BattleParticipant.create!(
        battle: battle, kingdom: @attacker, army: attacker_army, side: "attacker",
        starting_composition: { "knight" => 100 },
        ending_composition: attacker_after,
        casualties: { "knight" => 100 - attacker_after.fetch("knight", 0) }
      )
      BattleParticipant.create!(
        battle: battle, kingdom: @defender, army: defender_army, side: "defender",
        starting_composition: { "pikeman" => 50 },
        ending_composition: defender_after,
        casualties: { "pikeman" => 50 - defender_after.fetch("pikeman", 0) }
      )

      state = State.new(
        attacker_composition: attacker_after.dup,
        defender_aggregate: defender_after.dup,
        starting_attacker_composition: { "knight" => 100 },
        starting_defender_aggregate: { "pikeman" => 50 },
        total_starting_hp_attacker: 0,
        total_starting_hp_defender: 0,
        terrain: "plains",
        is_defender_home: true,
        walls_level: walls_level,
        walls_hp: walls_hp,
        rng: Random.new(1),
        log: []
      )
      [ battle, state, attacker_army, defender_army ]
    end

    test "attacker victory transfers loot capped by 25% and Warehouse" do
      battle, state, attacker_army, _ = build_battle_with_state(
        outcome: "attacker_victory",
        attacker_after: { "knight" => 80 },
        defender_after: { "pikeman" => 10 }
      )

      ApplyOutcome.call(battle: battle, state: state, walls_building: nil)

      defender_after = Stockpile::Read.call(@defender)
      attacker_after = Stockpile::Read.call(@attacker)

      battle.reload
      assert battle.loot.values.sum > 0, "expected non-zero loot on attacker victory"
      Kingdom::RESOURCES.each do |resource|
        assert_equal 4_000 - battle.loot[resource].to_i, defender_after[resource].to_i, "defender lost #{resource}"
        assert_equal battle.loot[resource].to_i, attacker_after[resource].to_i, "attacker gained #{resource}"
      end
      assert_equal "home", attacker_army.reload.status
    end

    test "defender victory: no loot transferred, attacker parks engaged" do
      battle, state, attacker_army, _ = build_battle_with_state(
        outcome: "defender_victory",
        attacker_after: { "knight" => 50 },
        defender_after: { "pikeman" => 40 }
      )
      ApplyOutcome.call(battle: battle, state: state, walls_building: nil)
      assert_equal({}, battle.reload.loot)
      assert_equal "engaged", attacker_army.reload.status
      assert_equal 0, Stockpile::Read.call(@attacker).values.sum
    end

    test "emptied non-Garrison defender army is destroyed" do
      battle, state, _, defender_army = build_battle_with_state(
        outcome: "attacker_victory",
        attacker_after: { "knight" => 80 },
        defender_after: { "pikeman" => 0 }
      )
      ApplyOutcome.call(battle: battle, state: state, walls_building: nil)
      refute Army.exists?(defender_army.id)
    end

    test "emptied Garrison defender army survives at zero composition" do
      # Rename defender to "Garrison" so it's protected.
      battle, state, _, defender_army = build_battle_with_state(
        outcome: "attacker_victory",
        attacker_after: { "knight" => 80 },
        defender_after: { "pikeman" => 0 }
      )
      defender_army.update!(name: Army::GARRISON_NAME)
      ApplyOutcome.call(battle: battle, state: state, walls_building: nil)
      assert Army.exists?(defender_army.id)
      assert_equal 0, defender_army.reload.composition.values.map(&:to_i).sum
    end

    test "wall level + HP persist after combat" do
      walls = @defender.buildings.find_by(kind: "walls")
      walls.update!(level: 5, wall_hp: 5_000)

      battle, state, _, _ = build_battle_with_state(
        outcome: "attacker_victory",
        attacker_after: { "knight" => 80 },
        defender_after: { "pikeman" => 25 },
        walls_level: 3,
        walls_hp: 2_500
      )
      ApplyOutcome.call(battle: battle, state: state, walls_building: walls)
      walls.reload
      assert_equal 3, walls.level
      assert_equal 2_500, walls.wall_hp
    end

    test "emits dun.battle.applied" do
      battle, state, _, _ = build_battle_with_state(
        outcome: "attacker_victory",
        attacker_after: { "knight" => 80 },
        defender_after: { "pikeman" => 10 }
      )
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.battle.applied") do
        ApplyOutcome.call(battle: battle, state: state, walls_building: nil)
      end
      assert_equal 1, events.size
      assert_equal battle.id, events.first[:battle_id]
    end
  end
end
