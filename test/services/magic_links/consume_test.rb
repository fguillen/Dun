require "test_helper"

module MagicLinks
  class ConsumeTest < ActiveSupport::TestCase
    test "consumes a player link, find-or-creates the Player, and issues an ApiKey" do
      record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

      result = MagicLinks::Consume.call(raw_token: raw_token, scope: "player")

      assert_instance_of Player, result.owner
      assert_equal "alice@example.com", result.owner.email
      assert_not_nil result.api_key
      assert_equal "Player", result.api_key.owner_type
      assert_not_nil result.raw_token
      assert record.reload.consumed_at.present?
    end

    test "rejects scope mismatch" do
      _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

      assert_raises(MagicLinks::Consume::ScopeMismatch) do
        MagicLinks::Consume.call(raw_token: raw_token, scope: "admin")
      end
    end

    test "rejects unknown tokens" do
      assert_raises(MagicLinks::Consume::InvalidToken) do
        MagicLinks::Consume.call(raw_token: "garbage", scope: "player")
      end
    end

    test "rejects double-consume" do
      _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")
      MagicLinks::Consume.call(raw_token: raw_token, scope: "player")

      assert_raises(MagicLink::AlreadyConsumed) do
        MagicLinks::Consume.call(raw_token: raw_token, scope: "player")
      end
    end

    test "reuses an existing Player by email" do
      existing = create(:player, email: "alice@example.com")
      _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

      result = MagicLinks::Consume.call(raw_token: raw_token, scope: "player")

      assert_equal existing, result.owner
    end
  end
end
