require "test_helper"

class PlayerTitleTest < ActiveSupport::TestCase
  setup do
    @profile = create(:player_profile)
    @world = create(:world, :active, server: @profile.server)
  end

  test "is valid with kind+awarded_at" do
    title = PlayerTitle.create!(player_profile: @profile, world: @world, awarded_at: Time.current)
    assert_equal "champion", title.kind
  end

  test "enforces uniqueness on (profile, world, kind)" do
    PlayerTitle.create!(player_profile: @profile, world: @world, awarded_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) do
      PlayerTitle.create!(player_profile: @profile, world: @world, awarded_at: Time.current)
    end
  end
end
