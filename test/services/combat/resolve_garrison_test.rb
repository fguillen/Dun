require "test_helper"

module Combat
  class ResolveGarrisonTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @home = create(:region, world: @world, terrain: "plains", name: "Home")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@home, @target)

      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @home)
    end

    def dispatch(army, target, intent: "capture")
      order = Marches::Dispatch.call(army: army, target_region: target, intent: intent)
      order.update!(arrives_at: 1.minute.ago)
      order
    end

    test "persists a Battle row with defender_kingdom_id: nil and two participants" do
      army = create(:army, kingdom: @kingdom, location_region: @home,
        composition: { "knight" => 100, "catapult" => 1 })
      order = dispatch(army, @target)

      battle = ResolveGarrison.call(march_order: order, garrison: { "levy" => 1 }, rng: Random.new(7))

      assert_equal 1, Battle.count
      assert_nil battle.defender_kingdom_id
      assert_equal 2, battle.participants.count
      defender = battle.participants.find_by(side: "defender")
      assert_nil defender.kingdom_id
      assert_nil defender.army_id
      assert_equal({ "levy" => 1 }, defender.starting_composition)
    end

    test "returns nil when garrison is empty" do
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "knight" => 10, "catapult" => 1 })
      order = dispatch(army, @target)
      battle = ResolveGarrison.call(march_order: order, garrison: {}, rng: Random.new(1))
      assert_nil battle
      assert_equal 0, Battle.count
    end

    test "emits dun.garrison.defeated" do
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "knight" => 100, "catapult" => 1 })
      order = dispatch(army, @target)
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.garrison.defeated") do
        ResolveGarrison.call(march_order: order, garrison: { "levy" => 1 }, rng: Random.new(7))
      end
      assert_equal 1, events.size
    end

    test "applies casualties to attacker army on victory and parks home at target" do
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "knight" => 100 })
      order = dispatch(army, @target)
      ResolveGarrison.call(march_order: order, garrison: { "levy" => 5 }, rng: Random.new(1))
      army.reload
      assert_equal "home", army.status
      assert_equal @target.id, army.location_region_id
    end

    test "attacker loses against an overwhelming garrison and is parked engaged (if not destroyed)" do
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "pikeman" => 50 })
      order = dispatch(army, @target)
      battle = ResolveGarrison.call(march_order: order, garrison: { "royal_guard" => 200 }, rng: Random.new(1))
      refute_includes %w[attacker_victory defender_rout], battle.outcome
      if Army.exists?(army.id)
        army.reload
        assert_equal "engaged", army.status
        assert_equal @target.id, army.location_region_id
      end
    end

    test "destroys an attacker army wiped to zero (non-garrison)" do
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "levy" => 1 })
      order = dispatch(army, @target)
      ResolveGarrison.call(march_order: order, garrison: { "royal_guard" => 100 }, rng: Random.new(2))
      refute Army.exists?(army.id)
    end
  end
end
