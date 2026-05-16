require "test_helper"

module Titles
  class AwardTest < ActiveSupport::TestCase
    setup do
      @profile = create(:player_profile)
      @world = create(:world, :active, server: @profile.server)
    end

    test "creates a champion title" do
      title = Award.call(player_profile: @profile, world: @world)
      assert_equal "champion", title.kind
      assert_equal @world.id, title.world_id
    end

    test "is idempotent for the same (profile, world, kind)" do
      Award.call(player_profile: @profile, world: @world)
      assert_no_difference -> { PlayerTitle.count } do
        Award.call(player_profile: @profile, world: @world)
      end
    end
  end
end
