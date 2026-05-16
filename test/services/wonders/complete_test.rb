require "test_helper"

module Wonders
  class CompleteTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @wonder = create(:wonder, :consecration, kingdom: @kingdom, hp: 10_000)
    end

    test "archives the world and sets winner + wonder_name" do
      events = []
      ActiveSupport::Notifications.subscribed(->(name, _, _, _, p) { events << [ name, p ] }, /dun\.(wonder|world)\./) do
        Complete.call(wonder: @wonder)
      end

      @wonder.reload
      @world.reload
      assert_equal "completed", @wonder.status
      assert_not_nil @wonder.completed_at
      assert_equal "archived", @world.status
      assert_equal @kingdom.id, @world.winner_kingdom_id
      assert_equal "sky_tower", @world.wonder_name
      assert_not_nil @world.archived_at

      kinds = events.map(&:first)
      assert_includes kinds, "dun.wonder.completed"
      assert_includes kinds, "dun.world.archived"
    end

    test "is a no-op if the Wonder is destroyed" do
      @wonder.update!(status: "destroyed", hp: 0)
      Complete.call(wonder: @wonder)
      @world.reload
      refute_equal "archived", @world.status
    end

    test "is a no-op if HP is 0 in consecration" do
      @wonder.update!(hp: 0)
      Complete.call(wonder: @wonder)
      assert_equal "consecration", @wonder.reload.status
      refute_equal "archived", @world.reload.status
    end
  end
end
