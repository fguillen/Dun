require "test_helper"

module Admins
  class InviteTest < ActiveSupport::TestCase
    setup do
      @server = create(:server)
      @owner  = @server.owner
    end

    test "creates a new Admin and grants adminship" do
      adminship = Admins::Invite.call(by_admin: @owner, server: @server, email: "new-admin@example.com")

      assert_equal "new-admin@example.com", adminship.admin.email
      assert_equal "admin", adminship.role
      assert_equal @owner, adminship.granted_by_admin
    end

    test "reuses an existing Admin record by email" do
      existing = create(:admin, email: "existing@example.com")

      adminship = Admins::Invite.call(by_admin: @owner, server: @server, email: "existing@example.com")

      assert_equal existing, adminship.admin
    end

    test "is idempotent on an existing adminship" do
      Admins::Invite.call(by_admin: @owner, server: @server, email: "new-admin@example.com")
      adminship = Admins::Invite.call(by_admin: @owner, server: @server, email: "new-admin@example.com")

      assert_equal 2, @server.server_adminships.count # owner + invited admin, no duplicate
      assert_equal "admin", adminship.role
    end
  end
end
