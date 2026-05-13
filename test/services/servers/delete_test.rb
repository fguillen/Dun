require "test_helper"

module Servers
  class DeleteTest < ActiveSupport::TestCase
    test "destroys the server" do
      admin = create(:admin)
      server = create(:server, owner: admin)

      Servers::Delete.call(server)

      assert_not Server.exists?(server.id)
    end

    test "cascades through dependent associations" do
      admin = create(:admin)
      server = create(:server, owner: admin)
      membership = create(:server_membership, server: server)
      profile    = create(:player_profile, server: server)
      access     = create(:server_access, server: server)

      Servers::Delete.call(server)

      assert_not ServerMembership.exists?(membership.id)
      assert_not PlayerProfile.exists?(profile.id)
      assert_not ServerAccess.exists?(access.id)
      assert_equal 0, ServerAdminship.where(server_id: server.id).count
    end
  end
end
