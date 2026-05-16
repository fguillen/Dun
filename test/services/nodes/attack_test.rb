require "test_helper"

module Nodes
  class AttackTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @attacker_home = create(:region, world: @world, terrain: "plains", name: "AttackerHome")
      @owner_home = create(:region, world: @world, terrain: "plains", name: "OwnerHome")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@attacker_home, @target)
      RegionAdjacency.connect(@owner_home, @target)

      @attacker = create(:kingdom, :with_buildings, world: @world, home_region: @attacker_home)
      @owner = create(:kingdom, :with_buildings, world: @world, home_region: @owner_home)

      @node = create(:node, region: @target, owner_kingdom_id: @owner.id, garrison: {})
    end

    def dispatch(army)
      order = Marches::Dispatch.call(army: army, target_region: @target, intent: "capture")
      order.update!(arrives_at: 1.minute.ago)
      order
    end

    test "transfers ownership immediately when the node is undefended (no battle)" do
      army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 10, "catapult" => 1 })
      order = dispatch(army)
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.node.captured") do
        Attack.call(march_order: order, node: @node, rng: Random.new(1))
      end
      @node.reload
      assert_equal @attacker.id, @node.owner_kingdom_id
      assert_equal 0, Battle.count
      assert_equal 1, events.size
      assert_nil events.first[:battle_id]
      army.reload
      assert_equal "home", army.status
      assert_equal @target.id, army.location_region_id
    end

    test "fights defending army at target (non-home region) and transfers ownership on win" do
      create(:army, kingdom: @owner, location_region: @target, name: "Guard",
        composition: { "levy" => 1 })
      army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 200, "catapult" => 1 })
      order = dispatch(army)

      battle = Attack.call(march_order: order, node: @node, rng: Random.new(7))
      assert_kind_of Battle, battle
      assert_equal @owner.id, battle.defender_kingdom_id
      assert_equal @target.id, battle.region_id
      @node.reload
      assert_equal @attacker.id, @node.owner_kingdom_id if %w[attacker_victory defender_rout].include?(battle.outcome)
    end

    test "raises CatapultRequired when attacker has no catapult" do
      army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 10 })
      order = dispatch(army)
      assert_raises(Attack::CatapultRequired) do
        Attack.call(march_order: order, node: @node, rng: Random.new(1))
      end
      @node.reload
      assert_equal @owner.id, @node.owner_kingdom_id
    end

    test "raises NotOwned when node is wilderness" do
      wild = create(:node, region: create(:region, world: @world, name: "Wild"))
      army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 10, "catapult" => 1 })
      order = dispatch(army)
      assert_raises(Attack::NotOwned) do
        Attack.call(march_order: order, node: wild, rng: Random.new(1))
      end
    end

    test "raises SelfAttack when the attacker already owns the node" do
      self_owned = create(:node, region: create(:region, world: @world, name: "Own"), owner_kingdom_id: @attacker.id, garrison: {})
      army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 10, "catapult" => 1 })
      order = dispatch(army)
      assert_raises(Attack::SelfAttack) do
        Attack.call(march_order: order, node: self_owned, rng: Random.new(1))
      end
    end
  end
end
