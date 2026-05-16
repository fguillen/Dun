require "test_helper"

module Wonders
  class EnterConsecrationTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 17)
      @kingdom.update!(stockpiles: {
        "gold" => 50_000, "wood" => 50_000, "stone" => 150_000, "iron" => 50_000,
        "checkpoint_at" => Time.current.iso8601
      })
      @wonder = create(:wonder,
        kingdom: @kingdom,
        status: "construction",
        hp: 10_000,
        milestones_paid: { "25" => true, "50" => true, "75" => true }
      )
    end

    test "transitions to consecration, deducts 5%, schedules complete +24h, emits notification" do
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.wonder.entered_consecration") do
        EnterConsecration.call(wonder: @wonder)
      end

      @wonder.reload
      assert_equal "consecration", @wonder.status
      assert_not_nil @wonder.consecration_at

      @kingdom.reload
      assert_equal 10_000, @kingdom.stockpile("gold")    # 50k - 40k
      assert_equal 20_000, @kingdom.stockpile("wood")    # 50k - 30k
      assert_equal 30_000, @kingdom.stockpile("stone")   # 150k - 120k
      assert_equal 10_000, @kingdom.stockpile("iron")    # 50k - 40k

      event = ScheduledEvent.pending
        .where(kind: "wonder_phase")
        .where("payload->>'wonder_id' = ?", @wonder.id)
        .where("payload->>'transition' = ?", "complete")
        .first
      assert event
      assert_in_delta @wonder.consecration_at + 24.hours, event.fire_at, 5

      assert_equal 1, events.size
    end

    test "re-schedules if Wonder hasn't reached target HP" do
      @wonder.update!(hp: 9_000)
      EnterConsecration.call(wonder: @wonder)

      assert_equal "construction", @wonder.reload.status
      next_event = ScheduledEvent.pending
        .where(kind: "wonder_phase")
        .where("payload->>'wonder_id' = ?", @wonder.id)
        .where("payload->>'transition' = ?", "enter_consecration")
        .first
      assert next_event
      assert_in_delta 1.hour.from_now, next_event.fire_at, 5
    end

    test "re-schedules if a milestone is unpaid" do
      @wonder.update!(milestones_paid: { "25" => true, "50" => true, "75" => false })
      EnterConsecration.call(wonder: @wonder)
      assert_equal "construction", @wonder.reload.status
    end

    test "re-schedules at +30m if Consecration payment is unaffordable" do
      @kingdom.update!(stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })
      EnterConsecration.call(wonder: @wonder)
      assert_equal "construction", @wonder.reload.status
      next_event = ScheduledEvent.pending
        .where(kind: "wonder_phase")
        .where("payload->>'wonder_id' = ?", @wonder.id)
        .where("payload->>'transition' = ?", "enter_consecration")
        .first
      assert next_event
      assert_in_delta 30.minutes.from_now, next_event.fire_at, 5
    end
  end
end
