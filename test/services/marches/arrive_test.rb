require "test_helper"

module Marches
  class ArriveTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace)
      @home = create(:region, world: @world, terrain: "plains", name: "Home")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@home, @target)

      kingdom = create(:kingdom, world: @world, home_region: @home)
      @army = create(:army, kingdom: kingdom, location_region: @home, name: "Vanguard",
        composition: { "knight" => 5 })
    end

    test "reinforce moves army to target and sets status home" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      order.update!(arrives_at: 1.minute.ago)

      Arrive.call(march_order: order)

      @army.reload
      assert_equal "home", @army.status
      assert_equal @target.id, @army.location_region_id
      assert_not_nil order.reload.arrived_at
    end

    test "scout sets status returning" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "scout")
      order.update!(arrives_at: 1.minute.ago)

      Arrive.call(march_order: order)
      assert_equal "returning", @army.reload.status
    end

    test "capture against a wilderness node invokes Nodes::Capture (fights garrison)" do
      node = create(:node, region: @target, garrison: { "levy" => 1 })
      @army.update!(composition: { "knight" => 50, "catapult" => 1 })
      order = Dispatch.call(army: @army, target_region: @target, intent: "capture")
      order.update!(arrives_at: 1.minute.ago)

      Arrive.call(march_order: order)

      assert_equal 1, Battle.count
      assert_nil Battle.last.defender_kingdom_id
      node.reload
      assert_equal @army.kingdom_id, node.owner_kingdom_id
    end

    # Dispatch normally rejects these up front; build the order via the factory to
    # exercise the in-transit arrival backstop directly.
    def capture_order_via_factory
      create(:march_order, army: @army, origin_region: @home, target_region: @target,
        intent: "capture", path: [ @home.id, @target.id ], arrives_at: 1.minute.ago)
    end

    test "capture without a catapult parks engaged + fires aborted notification (arrival backstop)" do
      create(:node, region: @target)
      order = capture_order_via_factory

      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.node.capture_aborted") do
        Arrive.call(march_order: order)
      end

      assert_equal "engaged", @army.reload.status
      assert_equal 1, events.size
      assert_equal "catapult_required", events.first[:reason]
      assert_equal 0, Battle.count
    end

    test "capture on a region with no node parks home and fires aborted (arrival backstop)" do
      events = []
      order = capture_order_via_factory

      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.node.capture_aborted") do
        Arrive.call(march_order: order)
      end

      assert_equal "home", @army.reload.status
      assert_equal "no_node", events.first[:reason]
    end

    test "claim_ruin invokes Ruins::Claim" do
      ruin = create(:ruin, :standard, region: @target, garrison: { "levy" => 1 })
      @army.update!(composition: { "knight" => 50 })
      order = Dispatch.call(army: @army, target_region: @target, intent: "claim_ruin")
      order.update!(arrives_at: 1.minute.ago)

      Arrive.call(march_order: order)

      assert_equal 1, Battle.count
      ruin.reload
      assert ruin.claimed?
      assert_equal @army.kingdom_id, ruin.claimed_by_kingdom_id
    end

    test "claim_ruin on a region without an unclaimed ruin fires aborted" do
      events = []
      order = Dispatch.call(army: @army, target_region: @target, intent: "claim_ruin")
      order.update!(arrives_at: 1.minute.ago)

      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.ruin.claim_aborted") do
        Arrive.call(march_order: order)
      end

      assert_equal "home", @army.reload.status
      assert_equal "no_unclaimed_ruin", events.first[:reason]
    end

    test "attack on an empty target parks the army home (no Battle row)" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "attack")
      order.update!(arrives_at: 1.minute.ago)
      Arrive.call(march_order: order)
      assert_equal "home", @army.reload.status
      assert_equal @target.id, @army.location_region_id
      assert_equal 0, Battle.count
    end

    test "attack against a defender creates a Battle and emits dun.battle.resolved" do
      defender = create(:kingdom, :with_buildings, world: @world, home_region: @target)
      defender.update!(stockpiles: { "gold" => 4_000, "wood" => 4_000, "stone" => 4_000, "iron" => 4_000, "checkpoint_at" => Time.current.iso8601 })
      create(:army, kingdom: defender, location_region: @target, name: "Garrison", composition: { "pikeman" => 30 })

      order = Dispatch.call(army: @army, target_region: @target, intent: "attack")
      order.update!(arrives_at: 1.minute.ago)

      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.battle.resolved") do
        Arrive.call(march_order: order)
      end

      assert_equal 1, Battle.count
      assert_equal 1, events.size
    end

    test "is idempotent on a second call" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      order.update!(arrives_at: 1.minute.ago)

      Arrive.call(march_order: order)
      first_arrived = order.reload.arrived_at

      Arrive.call(march_order: order)
      assert_equal first_arrived, order.reload.arrived_at
    end

    test "marks the matching ScheduledEvent processed" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      order.update!(arrives_at: 1.minute.ago)
      event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", order.id)
        .first
      assert event

      Arrive.call(march_order: order)
      assert event.reload.processed_at.present?
    end

    # Phase 8 — caravan intent routes to Caravans::Arrive (which delivers when
    # the destination is friendly). caravan_return routes to CompleteReturn.
    test "caravan intent routes to Caravans::Arrive (delivery happy path)" do
      server   = @world.server
      receiver_profile = create(:player_profile, server: server, handle: "Receiver")
      receiver = create(:kingdom, :with_buildings, world: @world, player_profile: receiver_profile,
        home_region: @target,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })
      sender = @army.kingdom
      sender_profile = create(:player_profile, server: server, handle: "Sender")
      sender.update!(player_profile: sender_profile)
      sender.update!(stockpiles: { "gold" => 500, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })

      caravan = Caravans::Dispatch.call(
        sender_kingdom: sender, receiver_kingdom: receiver,
        source_army: @army,
        payload: { "gold" => 100 }, escort_units: { "knight" => 2 })

      order = caravan.outbound_march_order
      order.update!(arrives_at: 1.minute.ago)

      Arrive.call(march_order: order)
      assert_equal "delivered", caravan.reload.status
    end

    test "caravan_return intent routes to Caravans::CompleteReturn" do
      server   = @world.server
      receiver_profile = create(:player_profile, server: server, handle: "Receiver")
      receiver = create(:kingdom, :with_buildings, world: @world, player_profile: receiver_profile,
        home_region: @target,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })
      sender = @army.kingdom
      sender_profile = create(:player_profile, server: server, handle: "Sender")
      sender.update!(player_profile: sender_profile)
      sender.update!(stockpiles: { "gold" => 500, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })

      caravan = Caravans::Dispatch.call(
        sender_kingdom: sender, receiver_kingdom: receiver,
        source_army: @army,
        payload: { "gold" => 100 }, escort_units: { "knight" => 2 })

      outbound = caravan.outbound_march_order
      outbound.update!(arrives_at: 1.minute.ago)
      Arrive.call(march_order: outbound)

      caravan.reload
      return_order = caravan.return_march_order
      assert return_order
      return_order.update!(arrives_at: 1.minute.ago)

      escort_id = caravan.escort_army_id
      Arrive.call(march_order: return_order)

      # Escort merged into sender's remaining home army (or converted in place).
      refute Army.exists?(escort_id) if escort_id  # merged or destroyed
    end

    test "emits dun.march_order.arrived" do
      order = Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
      order.update!(arrives_at: 1.minute.ago)
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.march_order.arrived") do
        Arrive.call(march_order: order)
      end

      assert_equal 1, events.size
      assert_equal "reinforce", events.first[:intent]
    end
  end
end
