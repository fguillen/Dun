require "test_helper"

module Training
  class QueueTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 1)
      @kingdom.buildings.find_by(kind: "stable").update!(level: 1)
      @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 1)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      stock(50_000)
    end

    def stock(amount)
      @kingdom.update!(stockpiles: {
        "gold" => amount, "wood" => amount, "stone" => amount, "iron" => amount,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "happy path: deducts cost × count, creates TrainingOrder" do
      order = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 5)

      assert_equal "levy", order.unit
      assert_equal 5, order.count
      assert_equal "barracks", order.building_kind
      assert order.completes_at > Time.current

      cost = Units::Catalog.cost_for("levy")
      @kingdom.reload
      assert_equal 50_000 - cost["gold"] * 5, @kingdom.stockpiles["gold"]
      assert_equal 50_000 - cost["wood"] * 5, @kingdom.stockpiles["wood"]
      assert_equal 50_000 - cost["iron"] * 5, @kingdom.stockpiles["iron"]
    end

    test "schedules a training_completion ScheduledEvent at completes_at" do
      order = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 3)

      event = ScheduledEvent.pending
        .where(kind: "training_completion")
        .where("payload->>'training_order_id' = ?", order.id)
        .first
      assert event, "expected a pending training_completion ScheduledEvent for the order"
      assert_in_delta order.completes_at, event.fire_at, 1
    end

    test "completes_at = now + per-unit time × count" do
      level = @kingdom.buildings.find_by(kind: "barracks").level
      per_unit = Units::TrainingTimeFor.call(unit: "levy", building_level: level)
      order = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 4)

      expected = order.started_at + per_unit * 4
      assert_in_delta expected, order.completes_at, 1
    end

    test "rejects unknown unit" do
      assert_raises(Queue::UnknownUnit) do
        Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "ninja", count: 1)
      end
    end

    test "rejects unknown building_kind" do
      assert_raises(Queue::BuildingMissing) do
        Queue.call(kingdom: @kingdom, building_kind: "warehouse", unit: "levy", count: 1)
      end
    end

    test "rejects building at level 0" do
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 0)
      assert_raises(Queue::BuildingMissing) do
        Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      end
    end

    test "rejects unit/building mismatch (levy at stable)" do
      assert_raises(Queue::UnitNotTrainableHere) do
        Queue.call(kingdom: @kingdom, building_kind: "stable", unit: "levy", count: 1)
      end
    end

    test "rejects insufficient resources" do
      stock(1)
      assert_raises(Stockpile::Apply::InsufficientResources) do
        Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      end
    end

    test "rejects when world is proposed" do
      @kingdom.world.update!(status: "proposed", grace_closes_at: nil, t0_at: 1.day.from_now)
      assert_raises(Queue::WorldNotBuildable) do
        Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      end
    end

    test "rejects when kingdom is eliminated" do
      @kingdom.update!(eliminated_at: 1.hour.ago)
      assert_raises(Queue::KingdomEliminated) do
        Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      end
    end

    test "rejects non-positive count" do
      assert_raises(ArgumentError) do
        Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 0)
      end
    end

    test "separate queues per military building (TODO line 249)" do
      barracks_order = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      stable_order   = Queue.call(kingdom: @kingdom, building_kind: "stable", unit: "knight", count: 1)
      siege_order    = Queue.call(kingdom: @kingdom, building_kind: "siege_workshop", unit: "catapult", count: 1)

      assert barracks_order.in_progress?
      assert stable_order.in_progress?
      assert siege_order.in_progress?
      assert_equal 3, @kingdom.training_orders.in_progress.count
    end

    test "second order at the same building does not block another building" do
      Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "archer", count: 1)
      stable_order = Queue.call(kingdom: @kingdom, building_kind: "stable", unit: "knight", count: 1)

      assert stable_order.in_progress?
      assert_equal 2, @kingdom.training_orders.in_progress.where(building_kind: "barracks").count
    end

    test "emits dun.training_order.queued" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.training_order.queued") do
        Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 2)
      end

      assert_equal 1, events.size
      assert_equal "levy", events.first[:unit]
      assert_equal 2, events.first[:count]
      assert_equal "barracks", events.first[:building_kind]
    end
  end
end
