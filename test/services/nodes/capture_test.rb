require "test_helper"

module Nodes
  class CaptureTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @home = create(:region, world: @world, terrain: "plains", name: "Home")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@home, @target)

      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @home)
    end

    # Build a march order directly (bypassing Marches::Dispatch) so the service is
    # exercised in isolation, including its in-transit backstop guards.
    def capture_order(army, target: @target)
      create(:march_order, army: army, origin_region: @home, target_region: target,
        intent: "capture", path: [ @home.id, target.id ], arrives_at: 1.minute.ago)
    end

    def army_with(composition)
      create(:army, kingdom: @kingdom, location_region: @home, composition: composition)
    end

    # --- Wilderness path (vs static garrison) ---

    test "wilderness node: raises CatapultRequired when the attacker has no catapult" do
      node = create(:node, region: @target)
      order = capture_order(army_with("knight" => 100))

      assert_raises(Capture::CatapultRequired) do
        Capture.call(march_order: order, node: node, rng: Random.new(1))
      end
      assert_equal Node::WILDERNESS_GARRISONS["standard"].transform_keys(&:to_s),
                   node.reload.garrison
      assert_nil node.owner_kingdom_id
    end

    test "wilderness node: transfers ownership and clears garrison on victory + emits dun.node.captured" do
      node = create(:node, region: @target, garrison: { "levy" => 1 })
      order = capture_order(army_with("knight" => 100, "catapult" => 1))
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.node.captured") do
        Capture.call(march_order: order, node: node, rng: Random.new(7))
      end

      node.reload
      assert_equal @kingdom.id, node.owner_kingdom_id
      assert_equal({}, node.garrison)
      assert_equal 1, events.size
      assert_equal node.id, events.first[:node_id]
    end

    test "wilderness node: on loss the node is unchanged (one-time defeat preserved)" do
      node = create(:node, region: @target, garrison: { "royal_guard" => 50 })
      order = capture_order(army_with("catapult" => 1, "levy" => 1))

      Capture.call(march_order: order, node: node, rng: Random.new(2))

      node.reload
      assert_nil node.owner_kingdom_id
      assert_equal({ "royal_guard" => 50 }, node.garrison.transform_keys(&:to_s).transform_values(&:to_i))
    end

    # --- Owned path (vs the owner's defending armies, or walk-in) ---

    test "owned node, undefended: walks in and transfers ownership (no battle)" do
      owner = create(:kingdom, :with_buildings, world: @world, home_region: create(:region, world: @world, name: "OwnerHome"))
      node = create(:node, region: @target, owner_kingdom_id: owner.id, garrison: {})
      army = army_with("knight" => 10, "catapult" => 1)
      order = capture_order(army)
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.node.captured") do
        Capture.call(march_order: order, node: node, rng: Random.new(1))
      end

      node.reload
      assert_equal @kingdom.id, node.owner_kingdom_id
      assert_equal 0, Battle.count
      assert_equal 1, events.size
      assert_nil events.first[:battle_id]
      army.reload
      assert_equal "home", army.status
      assert_equal @target.id, army.location_region_id
    end

    test "owned node, defended: fights the defender army and transfers ownership on win" do
      owner = create(:kingdom, :with_buildings, world: @world, home_region: create(:region, world: @world, name: "OwnerHome"))
      create(:army, kingdom: owner, location_region: @target, name: "Guard", composition: { "levy" => 1 })
      node = create(:node, region: @target, owner_kingdom_id: owner.id, garrison: {})
      order = capture_order(army_with("knight" => 200, "catapult" => 1))

      battle = Capture.call(march_order: order, node: node, rng: Random.new(7))
      assert_kind_of Battle, battle
      assert_equal owner.id, battle.defender_kingdom_id
      assert_equal @target.id, battle.region_id
      node.reload
      assert_equal @kingdom.id, node.owner_kingdom_id if %w[attacker_victory defender_rout].include?(battle.outcome)
    end

    test "raises SelfCapture when the attacker already owns the node" do
      node = create(:node, region: @target, owner_kingdom_id: @kingdom.id, garrison: {})
      order = capture_order(army_with("knight" => 10, "catapult" => 1))

      assert_raises(Capture::SelfCapture) do
        Capture.call(march_order: order, node: node, rng: Random.new(1))
      end
    end

    # --- Home-hoard protection ---

    test "raises HomeHoardProtected when capturing a wilderness home-hoard reserved for another kingdom" do
      rival_home = create(:region, world: @world, name: "RivalHome")
      create(:kingdom, :with_buildings, world: @world, home_region: rival_home)
      RegionAdjacency.connect(@home, rival_home)
      node = create(:node, region: rival_home, is_home_hoard: true) # wilderness, reserved for the rival
      order = capture_order(army_with("knight" => 10, "catapult" => 1), target: rival_home)

      assert_raises(Capture::HomeHoardProtected) do
        Capture.call(march_order: order, node: node, rng: Random.new(1))
      end
      assert_nil node.reload.owner_kingdom_id
    end

    test "raises HomeHoardProtected when attacking another kingdom's owned home-hoard" do
      rival_home = create(:region, world: @world, name: "RivalHome")
      rival = create(:kingdom, :with_buildings, world: @world, home_region: rival_home)
      RegionAdjacency.connect(@home, rival_home)
      node = create(:node, region: rival_home, is_home_hoard: true, owner_kingdom_id: rival.id, garrison: {})
      order = capture_order(army_with("knight" => 10, "catapult" => 1), target: rival_home)

      assert_raises(Capture::HomeHoardProtected) do
        Capture.call(march_order: order, node: node, rng: Random.new(1))
      end
      assert_equal rival.id, node.reload.owner_kingdom_id
    end

    test "the home kingdom can capture its own wilderness home-hoard" do
      node = create(:node, region: @home, is_home_hoard: true, garrison: { "levy" => 1 })
      army = army_with("knight" => 100, "catapult" => 1)
      order = create(:march_order, army: army, origin_region: @home, target_region: @home,
        intent: "capture", path: [ @home.id ], arrives_at: 1.minute.ago)

      Capture.call(march_order: order, node: node, rng: Random.new(7))

      assert_equal @kingdom.id, node.reload.owner_kingdom_id
    end
  end
end
