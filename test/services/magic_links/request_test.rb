require "test_helper"

module MagicLinks
  class RequestTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    test "creates a player-scope link and enqueues the mailer" do
      assert_enqueued_emails 1 do
        record = MagicLinks::Request.call(email: "Alice@Example.com", scope: "player")
        assert_equal "Player", record.owner_type
        assert_equal "alice@example.com", record.email
      end
    end

    test "creates an admin-scope link and enqueues the mailer" do
      assert_enqueued_emails 1 do
        record = MagicLinks::Request.call(email: "boss@example.com", scope: "admin")
        assert_equal "Admin", record.owner_type
      end
    end

    test "rejects unknown scopes" do
      assert_raises(ArgumentError) { MagicLinks::Request.call(email: "x@example.com", scope: "root") }
    end
  end
end
