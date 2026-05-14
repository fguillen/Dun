require "test_helper"

module Buildings
  class ResolveCompletionsTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 10) # 2 slots
      @kingdom.update!(stockpiles: {
        "gold" => 100_000, "wood" => 100_000, "stone" => 100_000, "iron" => 100_000,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "completes ripe orders in completes_at order" do
      a = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      b = Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
      a.update!(completes_at: 2.hours.ago)
      b.update!(completes_at: 1.hour.ago)

      ResolveCompletions.call(@kingdom)
      a.reload
      b.reload
      assert a.completed_at < b.completed_at
    end

    test "Stone Mason completes first, then resolves dependents under new discount" do
      stone_mason_order = Queue.call(kingdom: @kingdom, kind: "stone_mason", target_level: 1)
      quarry_order = Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      stone_mason_order.update!(started_at: 3.hours.ago, completes_at: 2.hours.ago)
      quarry_order.update!(started_at: 2.hours.ago, completes_at: 1.minute.ago)

      ResolveCompletions.call(@kingdom)
      assert_not_nil stone_mason_order.reload.completed_at
      assert_not_nil quarry_order.reload.completed_at
      assert_equal 1, @kingdom.buildings.find_by(kind: "stone_mason").reload.level
      assert_equal 2, @kingdom.buildings.find_by(kind: "quarry").reload.level
    end

    test "no-op when no orders are ripe" do
      Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      ResolveCompletions.call(@kingdom)
      assert_equal 1, @kingdom.buildings.find_by(kind: "quarry").reload.level
    end
  end
end
