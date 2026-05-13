require "test_helper"

class PlayerProfileLockedTest < ActiveSupport::TestCase
  test "profile is unlocked when no kingdom exists" do
    profile = create(:player_profile)
    refute profile.locked?
  end

  test "profile is locked when its kingdom is in a grace world" do
    world = create(:world, :grace)
    profile = create(:player_profile, server: world.server)
    create(:kingdom, world: world, player_profile: profile, home_region: create(:region, world: world))
    assert profile.locked?
  end

  test "profile is locked when its kingdom is in an active world" do
    world = create(:world, :active)
    profile = create(:player_profile, server: world.server)
    create(:kingdom, world: world, player_profile: profile, home_region: create(:region, world: world))
    assert profile.locked?
  end

  test "profile is unlocked when its only kingdom is in a proposed world" do
    world = create(:world, status: "proposed")
    profile = create(:player_profile, server: world.server)
    create(:kingdom, world: world, player_profile: profile, home_region: nil)
    refute profile.locked?
  end

  test "profile is unlocked when its only kingdom is in an archived world" do
    world = create(:world, :archived)
    profile = create(:player_profile, server: world.server)
    create(:kingdom, world: world, player_profile: profile, home_region: create(:region, world: world))
    refute profile.locked?
  end
end
