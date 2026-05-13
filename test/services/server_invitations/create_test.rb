require "test_helper"

module ServerInvitations
  class CreateTest < ActiveSupport::TestCase
    test "creates an invite-kind ServerAccess row" do
      server = create(:server)

      access = ServerInvitations::Create.call(server: server, email: "guest@example.com")

      assert_equal "invite", access.kind
      assert_equal "guest@example.com", access.value
    end

    test "is idempotent on the same (server, email)" do
      server = create(:server)
      ServerInvitations::Create.call(server: server, email: "guest@example.com")

      assert_no_difference -> { ServerAccess.count } do
        ServerInvitations::Create.call(server: server, email: "GUEST@example.com")
      end
    end
  end
end
