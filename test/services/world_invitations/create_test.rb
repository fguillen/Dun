require "test_helper"

module WorldInvitations
  class CreateTest < ActiveSupport::TestCase
    test "creates a normalized invitation" do
      admin = create(:admin)
      world = create(:world)

      inv = WorldInvitations::Create.call(world: world, by_admin: admin, email: "  Alice@Example.COM ")

      assert inv.persisted?
      assert_equal "alice@example.com", inv.email
      assert_equal admin, inv.invited_by_admin
    end

    test "is idempotent on duplicate emails (case-insensitive)" do
      admin = create(:admin)
      world = create(:world)

      a = WorldInvitations::Create.call(world: world, by_admin: admin, email: "x@y.com")
      b = WorldInvitations::Create.call(world: world, by_admin: admin, email: "X@Y.COM")

      assert_equal a.id, b.id
      assert_equal 1, world.world_invitations.count
    end
  end
end
