require "test_helper"

class WorldInvitationTest < ActiveSupport::TestCase
  test "factory builds a valid invitation" do
    inv = build(:world_invitation)
    assert inv.valid?, inv.errors.full_messages.join(", ")
  end

  test "email is normalized to lowercase and stripped" do
    inv = create(:world_invitation, email: "  Player@Example.COM ")
    assert_equal "player@example.com", inv.email
  end

  test "email format is validated" do
    inv = build(:world_invitation, email: "not-an-email")
    assert_not inv.valid?
    assert_includes inv.errors[:email], "is invalid"
  end

  test "email uniqueness is scoped per world, case-insensitive" do
    world = create(:world)
    create(:world_invitation, world: world, email: "x@y.com")
    dupe = build(:world_invitation, world: world, email: "X@Y.COM")
    assert_not dupe.valid?
  end

  test "same email allowed on different worlds" do
    create(:world_invitation, email: "x@y.com")
    twin = build(:world_invitation, email: "x@y.com")
    assert twin.valid?, twin.errors.full_messages.join(", ")
  end
end
