require "test_helper"

module Wonders
  class CancelTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @wonder = create(:wonder, kingdom: @kingdom, status: "construction")
    end

    test "abandoned Wonder is destroyed (full loss) and emits cancelled notification" do
      cancelled_events = []
      destroyed_events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { destroyed_events << p }, "dun.wonder.destroyed") do
        ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { cancelled_events << p }, "dun.wonder.cancelled") do
          Cancel.call(wonder: @wonder)
        end
      end
      @wonder.reload
      assert_equal "destroyed", @wonder.status
      assert_equal 1, cancelled_events.size
      assert_equal 1, destroyed_events.size
      assert_equal "cancelled", destroyed_events.first[:reason]
    end

    test "no-op on already-destroyed Wonder" do
      @wonder.update!(status: "destroyed", hp: 0, destroyed_at: Time.current)
      Cancel.call(wonder: @wonder)
      assert_equal "destroyed", @wonder.reload.status
    end
  end
end
