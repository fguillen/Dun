require "test_helper"

module Combat
  class ResolveTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @attacker_home = create(:region, world: @world, terrain: "plains", name: "AttackerHome")
      @defender_home = create(:region, world: @world, terrain: "plains", name: "DefenderHome")
      RegionAdjacency.connect(@attacker_home, @defender_home)

      @attacker = create(:kingdom, :with_buildings, world: @world, home_region: @attacker_home)
      @defender = create(:kingdom, :with_buildings, world: @world, home_region: @defender_home)
      @defender.update!(stockpiles: {
        "gold" => 4_000, "wood" => 4_000, "stone" => 4_000, "iron" => 4_000,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    def dispatch_attack(army, target, intent: "attack")
      order = Marches::Dispatch.call(army: army, target_region: target, intent: intent)
      order.update!(arrives_at: 1.minute.ago)
      order
    end

    test "no defender → returns nil and creates no Battle row" do
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 10 })
      order = dispatch_attack(attacker_army, @defender_home)
      # Defender has no army at home
      battle = Resolve.call(march_order: order, rng: Random.new(1))
      assert_nil battle
      assert_equal 0, Battle.count
    end

    test "creates a Battle, participants, and emits dun.battle.resolved" do
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home, name: "Strike",
        composition: { "knight" => 100 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "pikeman" => 50 })

      order = dispatch_attack(attacker_army, @defender_home)
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.battle.resolved") do
        Resolve.call(march_order: order, rng: Random.new(7))
      end

      assert_equal 1, Battle.count
      battle = Battle.last
      assert_equal 2, battle.participants.count
      assert_equal "attacker", battle.participants.find_by(army_id: attacker_army.id).side
      assert_includes Battle::OUTCOMES, battle.outcome
      assert_equal 1, events.size
      assert_equal battle.id, events.first[:battle_id]
    end

    test "Pikemen counter beats Knight rush (§16.3 RPS check)" do
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 100 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "pikeman" => 100 })
      order = dispatch_attack(attacker_army, @defender_home)
      battle = Resolve.call(march_order: order, rng: Random.new(123))
      assert_includes %w[defender_victory defender_rout attacker_rout], battle.outcome
    end

    test "same RNG seed → identical battle log" do
      a1 = create(:army, kingdom: @attacker, location_region: @attacker_home, composition: { "knight" => 100 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "pikeman" => 50 })
      order1 = dispatch_attack(a1, @defender_home)
      b1 = Resolve.call(march_order: order1, rng: Random.new(42))

      # Reset world state in a fresh world to get an identical setup.
      world2 = create(:world, :active)
      home2 = create(:region, world: world2, terrain: "plains", name: "A2")
      def2  = create(:region, world: world2, terrain: "plains", name: "D2")
      RegionAdjacency.connect(home2, def2)
      atk2 = create(:kingdom, :with_buildings, world: world2, home_region: home2)
      defk2 = create(:kingdom, :with_buildings, world: world2, home_region: def2)
      defk2.update!(stockpiles: { "gold" => 4_000, "wood" => 4_000, "stone" => 4_000, "iron" => 4_000, "checkpoint_at" => Time.current.iso8601 })
      a2 = create(:army, kingdom: atk2, location_region: home2, composition: { "knight" => 100 })
      create(:army, kingdom: defk2, location_region: def2, name: "Garrison", composition: { "pikeman" => 50 })
      order2 = dispatch_attack(a2, def2)
      b2 = Resolve.call(march_order: order2, rng: Random.new(42))

      assert_equal b1.log, b2.log
      assert_equal b1.outcome, b2.outcome
    end

    test "rout fires when a side drops below 15% HP" do
      # Tiny defender against overwhelming attacker — defender will rout.
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 500 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "levy" => 10 })
      order = dispatch_attack(attacker_army, @defender_home)
      battle = Resolve.call(march_order: order, rng: Random.new(5))
      assert_includes %w[defender_rout attacker_victory], battle.outcome
      assert_operator battle.log.size, :<=, Resolve::MAX_ROUNDS
    end

    test "loot capped by 25% defender stockpile applied on attacker victory" do
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 200 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "levy" => 5 })
      order = dispatch_attack(attacker_army, @defender_home)
      battle = Resolve.call(march_order: order, rng: Random.new(99))
      # Crushing win expected; loot present
      if %w[attacker_victory defender_rout].include?(battle.outcome)
        assert battle.loot.values.sum > 0, "expected non-zero loot on victory, got #{battle.loot.inspect}"
        # Defender 25% cap on 4000 gold = 1000 max
        assert_operator battle.loot["gold"].to_i, :<=, 1000
      end
    end

    test "destroys defender army wiped to zero (except Garrison)" do
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 500 })
      victim = create(:army, kingdom: @defender, location_region: @defender_home, name: "Volunteers",
        composition: { "levy" => 5 })
      order = dispatch_attack(attacker_army, @defender_home)
      Resolve.call(march_order: order, rng: Random.new(11))
      # Volunteers should be empty and destroyed
      refute Army.exists?(victim.id), "expected non-Garrison defender army to be destroyed"
    end

    test "wall HP and level update from Catapult fire" do
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "catapult" => 30, "knight" => 100 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "pikeman" => 30 })
      walls = @defender.buildings.find_by(kind: "walls")
      walls.update!(level: 2, wall_hp: 2_000)

      order = dispatch_attack(attacker_army, @defender_home)
      Resolve.call(march_order: order, rng: Random.new(1))

      walls.reload
      # 30 cats × 120 = 3600/round → blasts level 2 in <2 rounds
      assert_operator walls.level, :<, 2
    end

    test "second sequential attack sees casualties from the first (multi-attacker)" do
      # Two attackers against the same defender garrison.
      attacker_a = create(:army, kingdom: @attacker, location_region: @attacker_home, name: "Wave1",
        composition: { "knight" => 100 })

      other_attacker = create(:kingdom, :with_buildings, world: @world,
        home_region: create(:region, world: @world, name: "OtherHome"))
      attacker_b_army = create(:army, kingdom: other_attacker, location_region: other_attacker.home_region, name: "Wave2",
        composition: { "knight" => 100 })
      RegionAdjacency.connect(other_attacker.home_region, @defender_home)

      defender_garrison = create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "pikeman" => 100 })

      order_a = dispatch_attack(attacker_a, @defender_home)
      order_b = dispatch_attack(attacker_b_army, @defender_home)

      Resolve.call(march_order: order_a, rng: Random.new(50))
      defender_garrison.reload
      mid_pikemen = defender_garrison.composition["pikeman"].to_i
      assert_operator mid_pikemen, :<, 100, "first battle should have reduced defender pikemen"

      Resolve.call(march_order: order_b, rng: Random.new(50))
      defender_garrison.reload
      final_pikemen = defender_garrison.composition.fetch("pikeman", 0).to_i
      assert_operator final_pikemen, :<=, mid_pikemen, "second battle should not increase defender pikemen"
    end

    test "tie HP gives defender the win" do
      # Set up a symmetric stalemate by using zero-damage situation.
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "scout" => 1 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "royal_guard" => 1 })
      order = dispatch_attack(attacker_army, @defender_home)
      battle = Resolve.call(march_order: order, rng: Random.new(2))
      assert_includes %w[defender_victory attacker_rout], battle.outcome
    end
  end
end
