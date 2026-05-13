require "test_helper"

class KingdomTest < ActiveSupport::TestCase
  test "factory builds a valid kingdom" do
    kingdom = build(:kingdom)
    assert kingdom.valid?, kingdom.errors.full_messages.join(", ")
  end

  test "proposed trait permits a nil home_region" do
    kingdom = build(:kingdom, :proposed)
    assert kingdom.valid?, kingdom.errors.full_messages.join(", ")
    assert_nil kingdom.home_region_id
  end

  test "home_region is required once the world is past proposed" do
    world = create(:world, :grace)
    profile = create(:player_profile, server: world.server)
    kingdom = build(:kingdom, world: world, player_profile: profile, home_region: nil)
    assert_not kingdom.valid?
    assert_includes kingdom.errors[:home_region_id], "is required once the world has started"
  end

  test "rejects a player_profile whose server differs from the world's server" do
    world = create(:world, :grace)
    profile = create(:player_profile)  # different server by factory default
    kingdom = build(:kingdom, world: world, player_profile: profile, home_region: create(:region, world: world))
    assert_not kingdom.valid?
    assert_includes kingdom.errors[:player_profile], "must belong to the world's server"
  end

  test "uniqueness of player_profile per world" do
    world = create(:world, :grace)
    profile = create(:player_profile, server: world.server)
    region = create(:region, world: world)
    create(:kingdom, world: world, player_profile: profile, home_region: region)
    twin = build(:kingdom, world: world, player_profile: profile, home_region: create(:region, world: world))
    assert_not twin.valid?
  end

  test "joined_at defaults to now on create" do
    kingdom = create(:kingdom)
    assert_not_nil kingdom.joined_at
  end

  test "stub? mirrors absence of home_region_id" do
    assert build(:kingdom, :proposed).stub?
    refute build(:kingdom).stub?
  end
end
