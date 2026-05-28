require "test_helper"

module Events
  class FeedTest < ActiveSupport::TestCase
    def setup
      @server  = create(:server)
      @world   = create(:world, :active, server: @server)
      @region  = create(:region, world: @world)
      @profile = create(:player_profile, server: @server)
      @kingdom = create(:kingdom, world: @world, player_profile: @profile, home_region: @region)
      @other   = create(:kingdom, world: @world)
    end

    test "aggregates own build and training completions" do
      building = create(:building, kingdom: @kingdom, kind: "barracks", level: 3)
      create(:build_order, kingdom: @kingdom, building: building, target_level: 3, completed_at: 2.hours.ago)
      create(:training_order, kingdom: @kingdom, building: building, building_kind: "barracks",
        unit: "levy", count: 10, completed_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 10)

      build = events.find { |e| e.type == "build" }
      training = events.find { |e| e.type == "training" }
      assert_equal %(Building "barracks" finished upgrading to L3.), build.description
      assert_equal "Trained 10 levy at the barracks.", training.description
    end

    test "excludes another kingdom's private events" do
      other_building = create(:building, kingdom: @other, kind: "quarry", level: 1)
      create(:build_order, kingdom: @other, building: other_building, target_level: 2, completed_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 10)

      assert_empty events.select { |e| e.type == "build" }
    end

    test "emits a march dispatch event for the kingdom's armies" do
      target = create(:region, world: @world)
      army = create(:army, kingdom: @kingdom, name: "Legion 1")
      create(:march_order, army: army, origin_region: @region, target_region: target,
        intent: "attack", path: [ @region.id, target.id ], dispatched_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 10)

      march = events.find { |e| e.type == "march" }
      assert_equal %(Army "Legion 1" marched to #{target.name} (attack).), march.description
    end

    test "includes battles involving the kingdom and reflects the role" do
      create(:battle, world: @world, region: @region, attacker_kingdom: @kingdom,
        defender_kingdom: @other, outcome: "attacker_victory", ended_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 10)

      battle = events.find { |e| e.type == "battle" }
      assert_equal "Attacked at #{@region.name} — attacker victory.", battle.description
    end

    test "derives a capture event when an arrived capture-march left the kingdom owning a node" do
      target = create(:region, world: @world)
      army = create(:army, kingdom: @kingdom)
      create(:march_order, army: army, origin_region: @region, target_region: target,
        intent: "capture", path: [ @region.id, target.id ], arrived_at: 1.hour.ago)
      create(:node, region: target, owner_kingdom_id: @kingdom.id)

      events = Events::Feed.call(kingdom: @kingdom, limit: 10)

      capture = events.find { |e| e.type == "capture" }
      assert_equal "Captured a node in #{target.name}.", capture.description
    end

    test "omits a capture-march when no node ended owned by the kingdom" do
      target = create(:region, world: @world)
      army = create(:army, kingdom: @kingdom)
      create(:march_order, army: army, origin_region: @region, target_region: target,
        intent: "capture", path: [ @region.id, target.id ], arrived_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 10)

      assert_empty events.select { |e| e.type == "capture" }
    end

    test "includes world-public caravans from other kingdoms" do
      receiver = create(:kingdom, world: @world)
      create(:caravan, world: @world, sender_kingdom: @other, receiver_kingdom: receiver,
        payload: { "gold" => 500 }, status: "delivered",
        dispatched_at: 2.hours.ago, delivered_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 20)
      trades = events.select { |e| e.type == "trade" }

      assert trades.any? { |e| e.description.include?("dispatched") && e.description.include?("500 gold") }
      assert trades.any? { |e| e.description.include?("delivered") }
    end

    test "includes phase changes for any wonder in the world" do
      create(:wonder, :consecration, kingdom: @other, consecration_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 50)
      wonders = events.select { |e| e.type == "wonder" }

      assert wonders.any? { |e| e.description.include?("entered consecration") }
    end

    test "returns the most recent N events ordered oldest-first" do
      building = create(:building, kingdom: @kingdom, kind: "quarry", level: 1)
      create(:build_order, kingdom: @kingdom, building: building, target_level: 2, completed_at: 3.hours.ago)
      create(:build_order, kingdom: @kingdom, building: building, target_level: 3, completed_at: 2.hours.ago)
      create(:build_order, kingdom: @kingdom, building: building, target_level: 4, completed_at: 1.hour.ago)

      events = Events::Feed.call(kingdom: @kingdom, limit: 2)

      assert_equal 2, events.size
      assert events[0].occurred_at <= events[1].occurred_at
      assert_equal [
        %(Building "quarry" finished upgrading to L3.),
        %(Building "quarry" finished upgrading to L4.)
      ], events.map(&:description)
    end
  end
end
