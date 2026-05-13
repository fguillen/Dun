require "test_helper"

module Admins
  class RevokeAdminshipTest < ActiveSupport::TestCase
    setup do
      @server = create(:server)
      @owner  = @server.owner
    end

    test "removes an admin's adminship" do
      target = create(:admin)
      Admins::Invite.call(by_admin: @owner, server: @server, email: target.email)

      Admins::RevokeAdminship.call(by_admin: @owner, target_admin: target, server: @server)

      assert_not ServerAdminship.exists?(server: @server, admin: target)
      assert ServerAdminship.exists?(server: @server, admin: @owner)
    end

    test "raises LastAdminError when target is the last remaining admin" do
      assert_raises(Admins::LastAdminError) do
        Admins::RevokeAdminship.call(by_admin: @owner, target_admin: @owner, server: @server)
      end

      assert ServerAdminship.exists?(server: @server, admin: @owner)
    end

    test "raises RecordNotFound if target has no adminship on that server" do
      stranger = create(:admin)
      assert_raises(ActiveRecord::RecordNotFound) do
        Admins::RevokeAdminship.call(by_admin: @owner, target_admin: stranger, server: @server)
      end
    end
  end
end
