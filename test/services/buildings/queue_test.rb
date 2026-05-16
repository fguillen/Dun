require "test_helper"

module Buildings
  class QueueTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5) # cap 67_500
      stock(50_000)
    end

    def stock(amount)
      @kingdom.update!(stockpiles: {
        "gold" => amount, "wood" => amount, "stone" => amount, "iron" => amount,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "happy path: deducts cost, creates BuildOrder" do
      order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)

      assert_equal 2, order.target_level
      assert order.completes_at > Time.current
      @kingdom.reload
      cost = CostFor.call(kind: "quarry", level: 2)
      assert_equal 50_000 - cost["gold"], @kingdom.stockpiles["gold"]
    end

    test "schedules a build_completion ScheduledEvent at completes_at" do
      order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)

      event = ScheduledEvent.pending
        .where(kind: "build_completion")
        .where("payload->>'build_order_id' = ?", order.id)
        .first
      assert event, "expected a pending build_completion ScheduledEvent for the order"
      assert_in_delta order.completes_at, event.fire_at, 1
    end

    test "tier gate: stable requires barracks 3" do
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 2)
      err = assert_raises(Queue::TierGateUnmet) do
        Queue.call(kingdom: @kingdom, kind: "stable", target_level: 1)
      end
      assert_match "barracks", err.message
    end

    test "tier gate: siege workshop requires barracks 5 AND iron mine 5" do
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 5)
      @kingdom.buildings.find_by(kind: "iron_mine").update!(level: 4)
      assert_raises(Queue::TierGateUnmet) do
        Queue.call(kingdom: @kingdom, kind: "siege_workshop", target_level: 1)
      end
    end

    test "single slot rule (no Town Hall L10)" do
      Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      assert_raises(Queue::QueueFull) do
        Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
      end
    end

    test "Town Hall L10 unlocks a second slot" do
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 10)
      Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
      assert_raises(Queue::QueueFull) do
        Queue.call(kingdom: @kingdom, kind: "iron_mine", target_level: 2)
      end
    end

    test "Town Hall L20 unlocks a third slot" do
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 20)
      Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
      Queue.call(kingdom: @kingdom, kind: "iron_mine", target_level: 2)
      assert_raises(Queue::QueueFull) do
        Queue.call(kingdom: @kingdom, kind: "lumber_camp", target_level: 2)
      end
    end

    test "idempotent retry returns existing order without re-deducting" do
      first = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      gold_after_first = @kingdom.reload.stockpiles["gold"]
      second = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      assert_equal first.id, second.id
      assert_equal gold_after_first, @kingdom.reload.stockpiles["gold"]
    end

    test "target_level must equal current + 1" do
      assert_raises(Queue::InvalidTargetLevel) do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 3)
      end
    end

    test "target_level cannot exceed MAX_LEVEL" do
      @kingdom.buildings.find_by(kind: "quarry").update!(level: 20)
      assert_raises(Queue::InvalidTargetLevel) do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 21)
      end
    end

    test "unknown building rejected" do
      assert_raises(Queue::UnknownBuilding) do
        Queue.call(kingdom: @kingdom, kind: "castle", target_level: 1)
      end
    end

    test "insufficient resources rejected" do
      stock(10)
      assert_raises(Stockpile::Apply::InsufficientResources) do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      end
    end

    test "rejects when world is proposed" do
      @kingdom.world.update!(status: "proposed", grace_closes_at: nil, t0_at: 1.day.from_now)
      assert_raises(Queue::WorldNotBuildable) do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      end
    end

    test "rejects when world is archived" do
      @kingdom.world.update!(status: "archived", archived_at: 1.hour.ago)
      assert_raises(Queue::WorldNotBuildable) do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      end
    end

    test "rejects when kingdom is eliminated" do
      @kingdom.update!(eliminated_at: 1.hour.ago)
      assert_raises(Queue::KingdomEliminated) do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      end
    end

    test "rejects when a live Wonder is in progress" do
      create(:wonder, kingdom: @kingdom, status: "construction")
      assert_raises(Queue::WonderInProgress) do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      end
    end

    test "allows builds after the Wonder is destroyed" do
      wonder = create(:wonder, kingdom: @kingdom, status: "construction")
      wonder.update!(status: "destroyed", destroyed_at: 1.minute.ago)
      assert_nothing_raised do
        Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      end
    end
  end
end
