require "test_helper"

module Wonders
  class DestroyTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @wonder = create(:wonder, kingdom: @kingdom, status: "construction")
      create(:scheduled_event,
        world: @world,
        kind: "wonder_phase",
        fire_at: 90.hours.from_now,
        payload: { "wonder_id" => @wonder.id, "transition" => "enter_consecration" })
    end

    test "flips status to destroyed and cancels pending wonder_phase events" do
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.wonder.destroyed") do
        Destroy.call(wonder: @wonder)
      end

      @wonder.reload
      assert_equal "destroyed", @wonder.status
      assert_not_nil @wonder.destroyed_at

      assert_equal 0, ScheduledEvent.pending
        .where(kind: "wonder_phase")
        .where("payload->>'wonder_id' = ?", @wonder.id).count

      assert_equal 1, events.size
      assert_equal "damage", events.first[:reason]
    end

    test "is idempotent on an already-destroyed Wonder" do
      Destroy.call(wonder: @wonder)
      Destroy.call(wonder: @wonder)  # no error, no extra side effects
      assert_equal "destroyed", @wonder.reload.status
    end
  end
end
