require "test_helper"

class PlayerProfileTest < ActiveSupport::TestCase
  setup do
    @server = create(:server)
    @player = create(:player)
  end

  test "factory builds a valid profile" do
    profile = build(:player_profile, server: @server, player: @player)
    assert profile.valid?, profile.errors.full_messages.join(", ")
  end

  test "handle and real_name may be nil at first" do
    profile = PlayerProfile.new(server: @server, player: @player)
    assert profile.valid?
  end

  test "rejects reserved handles (case-insensitive)" do
    PlayerProfile::RESERVED_HANDLES.each do |reserved|
      [ reserved, reserved.upcase, reserved.capitalize ].each do |variant|
        next if variant.length < 3 # length check happens first
        profile = build(:player_profile, server: @server, player: @player, handle: variant)
        assert_not profile.valid?, "expected #{variant.inspect} to be invalid"
        assert_includes profile.errors[:handle], "is reserved"
      end
    end
  end

  test "handle may start with a digit" do
    profile = build(:player_profile, server: @server, player: @player, handle: "1Fist")
    assert profile.valid?, profile.errors.full_messages.join(", ")
  end

  test "handle rejects spaces" do
    [ "Iron Fist", " Lead", "Trail ", "Double  Space" ].each do |bad|
      profile = build(:player_profile, server: @server, player: @player, handle: bad)
      assert_not profile.valid?, "expected #{bad.inspect} to be invalid"
    end
  end

  test "handle accepts letters, digits, underscores, and hyphens" do
    profile = build(:player_profile, server: @server, player: @player, handle: "Iron-Fist_42")
    assert profile.valid?, profile.errors.full_messages.join(", ")
  end

  test "handle uniqueness is case-insensitive within a server" do
    create(:player_profile, server: @server, player: @player, handle: "IronFist")
    other_player = create(:player)
    dup = build(:player_profile, server: @server, player: other_player, handle: "ironfist")
    assert_not dup.valid?
  end

  test "same handle is allowed on different servers" do
    create(:player_profile, server: @server, player: @player, handle: "IronFist")
    other_server = create(:server)
    other_player = create(:player)
    dup = build(:player_profile, server: other_server, player: other_player, handle: "ironfist")
    assert dup.valid?, dup.errors.full_messages.join(", ")
  end

  test "real_name length 1..60" do
    profile = build(:player_profile, server: @server, player: @player, real_name: "")
    assert_not profile.valid?
    profile.real_name = "x" * 61
    assert_not profile.valid?
    profile.real_name = "Fernando"
    assert profile.valid?
  end

  test "handle length 3..24" do
    profile = build(:player_profile, server: @server, player: @player, handle: "ab")
    assert_not profile.valid?
    profile.handle = "a" * 24
    assert profile.valid?, profile.errors.full_messages.join(", ")
    profile.handle = "a" * 25
    assert_not profile.valid?
  end

  test "locked? is false until Phase 2 lands" do
    profile = build(:player_profile)
    assert_not profile.locked?
  end
end
