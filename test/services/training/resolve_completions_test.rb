require "test_helper"

module Training
  class ResolveCompletionsTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom, :with_buildings)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 1)
      @kingdom.buildings.find_by(kind: "stable").update!(level: 1)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
      @kingdom.update!(stockpiles: {
        "gold" => 50_000, "wood" => 50_000, "stone" => 50_000, "iron" => 50_000,
        "checkpoint_at" => Time.current.iso8601
      })
    end

    test "completes ripe orders in completes_at order" do
      a = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      b = Queue.call(kingdom: @kingdom, building_kind: "stable", unit: "knight", count: 1)
      a.update!(completes_at: 2.hours.ago)
      b.update!(completes_at: 1.hour.ago)

      ResolveCompletions.call(@kingdom)

      a.reload
      b.reload
      assert a.completed_at < b.completed_at
    end

    test "leaves future orders alone" do
      future = Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
      future.update!(completes_at: 1.hour.from_now)

      ResolveCompletions.call(@kingdom)
      assert future.reload.in_progress?
    end
  end
end
