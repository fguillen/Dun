require "test_helper"

module Training
  class CompleteTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 1)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      @kingdom.update!(stockpiles: {
        "gold" => 50_000, "wood" => 50_000, "stone" => 50_000, "iron" => 50_000,
        "checkpoint_at" => Time.current.iso8601
      })
      @order = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 5)
    end

    test "creates the home garrison if absent and merges trained units" do
      Complete.call(training_order: @order)

      garrison = @kingdom.armies.find_by(name: Army::GARRISON_NAME)
      assert garrison, "garrison auto-created"
      assert_equal @kingdom.home_region_id, garrison.location_region_id
      assert_equal "home", garrison.status
      assert_equal 5, garrison.composition["levy"]
    end

    test "merges into an existing garrison" do
      garrison = create(:army, kingdom: @kingdom, name: Army::GARRISON_NAME,
        location_region: @kingdom.home_region, composition: { "levy" => 3, "archer" => 2 })

      Complete.call(training_order: @order)
      garrison.reload
      assert_equal 8, garrison.composition["levy"]
      assert_equal 2, garrison.composition["archer"]
    end

    test "sets completed_at" do
      Complete.call(training_order: @order)
      assert_not_nil @order.reload.completed_at
    end

    test "is idempotent on a second call" do
      Complete.call(training_order: @order)
      first_completed_at = @order.reload.completed_at

      Complete.call(training_order: @order)
      assert_equal first_completed_at, @order.reload.completed_at

      garrison = @kingdom.armies.find_by(name: Army::GARRISON_NAME)
      assert_equal 5, garrison.composition["levy"]
    end

    test "marks the matching ScheduledEvent processed" do
      event = ScheduledEvent.pending
        .where(kind: "training_completion")
        .where("payload->>'training_order_id' = ?", @order.id)
        .first
      assert event

      Complete.call(training_order: @order)
      assert event.reload.processed_at.present?
    end

    test "emits dun.training_order.completed" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.training_order.completed") do
        Complete.call(training_order: @order)
      end

      assert_equal 1, events.size
      assert_equal "levy", events.first[:unit]
      assert_equal 5, events.first[:count]
      assert_equal "barracks", events.first[:building_kind]
    end
  end
end
