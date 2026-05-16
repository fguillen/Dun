require "test_helper"

module ScheduledEvents
  class DispatchTest < ActiveSupport::TestCase
    test "build_completion handler completes the build order and marks the event processed" do
      kingdom = create(:kingdom, :with_buildings)
      building = kingdom.buildings.find_by(kind: "quarry")
      order = create(:build_order, kingdom: kingdom, building: building, target_level: 2, completes_at: 1.minute.ago)
      event = create(:scheduled_event,
        world: kingdom.world,
        kind: "build_completion",
        fire_at: 1.minute.ago,
        payload: { "build_order_id" => order.id })

      Dispatch.call(event)

      assert event.reload.processed_at.present?
      assert order.reload.completed_at.present?
      assert_equal 2, building.reload.level
    end

    test "build_completion is a no-op when the build order has been deleted" do
      world = create(:world, :active)
      event = create(:scheduled_event,
        world: world,
        kind: "build_completion",
        fire_at: 1.minute.ago,
        payload: { "build_order_id" => "01HZZZZZZZZZZZZZZZZZZZZZZZ" })

      assert_nothing_raised { Dispatch.call(event) }
      assert event.reload.processed_at.present?
    end

    test "grace_expiry handler transitions world to active" do
      world = create(:world, :grace)
      event = create(:scheduled_event,
        world: world,
        kind: "grace_expiry",
        fire_at: 1.minute.ago)

      Dispatch.call(event)

      assert_equal "active", world.reload.status
      assert event.reload.processed_at.present?
    end

    test "training_completion handler completes the order and marks event processed" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "barracks").update!(level: 1)
      order = create(:training_order, kingdom: kingdom,
        building: kingdom.buildings.find_by(kind: "barracks"),
        building_kind: "barracks", unit: "levy", count: 3,
        completes_at: 1.minute.ago)
      event = create(:scheduled_event,
        world: kingdom.world,
        kind: "training_completion",
        fire_at: 1.minute.ago,
        payload: { "training_order_id" => order.id })

      Dispatch.call(event)

      assert event.reload.processed_at.present?
      assert order.reload.completed_at.present?
      garrison = kingdom.armies.find_by(name: Army::GARRISON_NAME)
      assert_equal 3, garrison.composition["levy"]
    end

    test "training_completion is a no-op when the order has been deleted" do
      world = create(:world, :active)
      event = create(:scheduled_event,
        world: world,
        kind: "training_completion",
        fire_at: 1.minute.ago,
        payload: { "training_order_id" => "01HZZZZZZZZZZZZZZZZZZZZZZZ" })

      assert_nothing_raised { Dispatch.call(event) }
      assert event.reload.processed_at.present?
    end

    test "march_arrival handler arrives the order and marks event processed" do
      world = create(:world, :grace)
      home = create(:region, world: world, name: "Home")
      target = create(:region, world: world, name: "Target")
      RegionAdjacency.connect(home, target)
      kingdom = create(:kingdom, world: world, home_region: home)
      army = create(:army, kingdom: kingdom, location_region: home, name: "Alpha",
        composition: { "knight" => 1 })
      order = ::Marches::Dispatch.call(army: army, target_region: target, intent: "reinforce")
      order.update!(arrives_at: 1.minute.ago)
      event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", order.id)
        .first

      Dispatch.call(event)

      assert event.reload.processed_at.present?
      assert order.reload.arrived_at.present?
      assert_equal target.id, army.reload.location_region_id
    end

    test "march_arrival is a no-op when the march order has been deleted" do
      world = create(:world, :active)
      event = create(:scheduled_event,
        world: world,
        kind: "march_arrival",
        fire_at: 1.minute.ago,
        payload: { "march_order_id" => "01HZZZZZZZZZZZZZZZZZZZZZZZ" })

      assert_nothing_raised { Dispatch.call(event) }
      assert event.reload.processed_at.present?
    end

    test "no-op on already-processed event" do
      event = create(:scheduled_event, processed_at: 1.minute.ago)
      Dispatch.call(event)
      assert_in_delta 1.minute.ago, event.reload.processed_at, 5
    end

    test "unknown kind raises and leaves event pending" do
      world = create(:world, :active)
      event = ScheduledEvent.create!(
        world: world,
        kind: "weather_edge",
        fire_at: 1.minute.ago
      )

      assert_raises(Dispatch::UnknownKind) { Dispatch.call(event) }
      assert event.reload.pending?
    end

    test "wonder_phase enter_consecration handler transitions Wonder" do
      world = create(:world, :active)
      kingdom = create(:kingdom, :with_buildings, world: world, home_region: create(:region, world: world))
      kingdom.buildings.find_by(kind: "warehouse").update!(level: 17)
      kingdom.update!(stockpiles: { "gold" => 50_000, "wood" => 50_000, "stone" => 150_000, "iron" => 50_000, "checkpoint_at" => Time.current.iso8601 })
      wonder = create(:wonder, kingdom: kingdom, status: "construction", hp: 10_000,
        milestones_paid: { "25" => true, "50" => true, "75" => true })
      event = create(:scheduled_event,
        world: world,
        kind: "wonder_phase",
        fire_at: 1.minute.ago,
        payload: { "wonder_id" => wonder.id, "transition" => "enter_consecration" })

      Dispatch.call(event)

      assert event.reload.processed_at.present?
      assert_equal "consecration", wonder.reload.status
    end

    test "wonder_phase complete handler archives the world" do
      world = create(:world, :active)
      kingdom = create(:kingdom, :with_buildings, world: world, home_region: create(:region, world: world))
      wonder = create(:wonder, :consecration, kingdom: kingdom)
      event = create(:scheduled_event,
        world: world,
        kind: "wonder_phase",
        fire_at: 1.minute.ago,
        payload: { "wonder_id" => wonder.id, "transition" => "complete" })

      Dispatch.call(event)

      assert event.reload.processed_at.present?
      assert_equal "completed", wonder.reload.status
      assert_equal "archived", world.reload.status
    end

    test "wonder_phase is a no-op when the Wonder has been deleted" do
      world = create(:world, :active)
      event = create(:scheduled_event,
        world: world,
        kind: "wonder_phase",
        fire_at: 1.minute.ago,
        payload: { "wonder_id" => "01HZZZZZZZZZZZZZZZZZZZZZZZ", "transition" => "complete" })

      assert_nothing_raised { Dispatch.call(event) }
      assert event.reload.processed_at.present?
    end

    test "emits dun.scheduled_event.processed notification" do
      world = create(:world, :grace)
      event = create(:scheduled_event, world: world, kind: "grace_expiry", fire_at: 1.minute.ago)

      captured = nil
      ActiveSupport::Notifications.subscribed(
        ->(_name, _start, _finish, _id, payload) { captured = payload },
        "dun.scheduled_event.processed"
      ) do
        Dispatch.call(event)
      end

      assert_equal "grace_expiry", captured[:kind]
      assert_equal event.id, captured[:event_id]
    end
  end
end
