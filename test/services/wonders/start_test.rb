require "test_helper"

module Wonders
  class StartTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 17)
      @kingdom.update!(stockpiles: {
        "gold" => 300_000, "wood" => 300_000, "stone" => 700_000, "iron" => 300_000,
        "checkpoint_at" => Time.current.iso8601
      })
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 10)
      @kingdom.buildings.find_by(kind: "quarry").update!(level: 10)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 5)
      @kingdom.buildings.find_by(kind: "iron_mine").update!(level: 5)
      @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 5)
      3.times { |i| create(:node, region: create(:region, world: @world, name: "n-#{i}"), owner_kingdom_id: @kingdom.id) }
    end

    test "happy path: deducts 25% foundation, creates Wonder in construction status" do
      wonder = nil
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.wonder.started") do
        wonder = Start.call(kingdom: @kingdom, name: "sky_tower")
      end

      assert_equal "construction", wonder.status
      assert_equal 1_000, wonder.hp
      assert_equal 10_000, wonder.target_hp
      assert_equal "sky_tower", wonder.name
      assert_not_nil wonder.started_at
      assert_not_nil wonder.construction_started_at
      assert_not_nil wonder.last_construction_at

      @kingdom.reload
      assert_equal 100_000, @kingdom.stockpile("gold")  # 300_000 - 200_000
      assert_equal 150_000, @kingdom.stockpile("wood")  # 300_000 - 150_000
      assert_equal 100_000, @kingdom.stockpile("stone") # 700_000 - 600_000
      assert_equal 100_000, @kingdom.stockpile("iron")  # 300_000 - 200_000

      assert_equal 1, events.size
      assert_equal wonder.id, events.first[:wonder_id]
    end

    test "schedules a wonder_phase event +90h to enter consecration" do
      wonder = Start.call(kingdom: @kingdom, name: "sky_tower")

      event = ScheduledEvent.pending
        .where(world_id: @world.id, kind: "wonder_phase")
        .where("payload->>'wonder_id' = ?", wonder.id)
        .first
      assert event
      assert_equal "enter_consecration", event.payload["transition"]
      assert_in_delta wonder.started_at + 90.hours, event.fire_at, 1
    end

    test "rejects unknown wonder name" do
      assert_raises(Start::UnknownName) { Start.call(kingdom: @kingdom, name: "atlantis") }
    end

    test "rejects when prereqs are unmet" do
      @kingdom.buildings.find_by(kind: "quarry").update!(level: 9)
      assert_raises(Prerequisites::NotMet) { Start.call(kingdom: @kingdom, name: "sky_tower") }
    end
  end
end
