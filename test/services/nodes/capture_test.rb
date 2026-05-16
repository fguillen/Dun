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

    def dispatch(army)
      order = Marches::Dispatch.call(army: army, target_region: @target, intent: "capture")
      order.update!(arrives_at: 1.minute.ago)
      order
    end

    test "raises CatapultRequired when the attacker has no catapult" do
      node = create(:node, region: @target)
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "knight" => 100 })
      order = dispatch(army)

      assert_raises(Capture::CatapultRequired) do
        Capture.call(march_order: order, node: node, rng: Random.new(1))
      end
      assert_equal Node::WILDERNESS_GARRISONS["standard"].transform_keys(&:to_s),
                   node.reload.garrison
      assert_nil node.owner_kingdom_id
    end

    test "transfers ownership and clears garrison on victory + emits dun.node.captured" do
      node = create(:node, region: @target, garrison: { "levy" => 1 })
      army = create(:army, kingdom: @kingdom, location_region: @home,
        composition: { "knight" => 100, "catapult" => 1 })
      order = dispatch(army)
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.node.captured") do
        Capture.call(march_order: order, node: node, rng: Random.new(7))
      end

      node.reload
      assert_equal @kingdom.id, node.owner_kingdom_id
      assert_equal({}, node.garrison)
      assert_equal 1, events.size
      assert_equal node.id, events.first[:node_id]

      army.reload
      assert_equal "home", army.status
      assert_equal @target.id, army.location_region_id
    end

    test "on loss the node is unchanged (one-time defeat: garrison preserved for next attacker)" do
      garrison_comp = { "royal_guard" => 50 }
      node = create(:node, region: @target, garrison: garrison_comp)
      army = create(:army, kingdom: @kingdom, location_region: @home,
        composition: { "catapult" => 1, "levy" => 1 })
      order = dispatch(army)

      Capture.call(march_order: order, node: node, rng: Random.new(2))

      node.reload
      assert_nil node.owner_kingdom_id
      # Garrison is preserved verbatim — no respawn, no partial-attrition wear.
      assert_equal({ "royal_guard" => 50 }, node.garrison.transform_keys(&:to_s).transform_values(&:to_i))
    end

    test "raises AlreadyOwned when the node already has an owner" do
      other = create(:kingdom, world: @world, home_region: create(:region, world: @world, name: "Other"))
      node = create(:node, region: @target, owner_kingdom_id: other.id, garrison: {})
      army = create(:army, kingdom: @kingdom, location_region: @home,
        composition: { "catapult" => 1, "knight" => 10 })
      order = dispatch(army)
      assert_raises(Capture::AlreadyOwned) do
        Capture.call(march_order: order, node: node, rng: Random.new(1))
      end
    end
  end
end
