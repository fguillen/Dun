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

    test "capture/claim_ruin park the army as engaged (Phase 7 stub)" do
      %w[capture claim_ruin].each do |intent|
        @army.update!(status: "home", location_region_id: @home.id)
        order = Dispatch.call(army: @army, target_region: @target, intent: intent)
        order.update!(arrives_at: 1.minute.ago)

        Arrive.call(march_order: order)
        assert_equal "engaged", @army.reload.status
        assert_equal @target.id, @army.location_region_id
      end
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
