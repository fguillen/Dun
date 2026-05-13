require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  test "generate_for stores only the digest and sets a 90-day expiry" do
    player = create(:player)

    record, raw_token = ApiKey.generate_for(owner: player)

    assert_not_nil raw_token
    assert_equal Digest::SHA256.hexdigest(raw_token), record.token_digest
    assert record.expires_at > 89.days.from_now
    assert record.expires_at < 91.days.from_now
    assert_nil record.revoked_at
    assert_equal "Player", record.owner_type
  end

  test "authenticate returns nil for unknown tokens" do
    assert_nil ApiKey.authenticate("garbage", owner_type: "Player")
    assert_nil ApiKey.authenticate(nil, owner_type: "Player")
    assert_nil ApiKey.authenticate("", owner_type: "Player")
  end

  test "authenticate refreshes last_used_at and slides expiry forward" do
    player = create(:player)
    record, raw_token = ApiKey.generate_for(owner: player)
    record.update_columns(last_used_at: 5.days.ago, expires_at: 60.days.from_now)

    key, owner = ApiKey.authenticate(raw_token, owner_type: "Player")

    assert_equal record, key
    assert_equal player, owner
    assert key.last_used_at > 1.minute.ago
    assert key.expires_at > 89.days.from_now
  end

  test "authenticate enforces owner_type scoping" do
    player = create(:player)
    _record, raw_token = ApiKey.generate_for(owner: player)

    assert_nil ApiKey.authenticate(raw_token, owner_type: "Admin")
  end

  test "authenticate rejects revoked keys" do
    player = create(:player)
    record, raw_token = ApiKey.generate_for(owner: player)
    record.revoke!

    assert_nil ApiKey.authenticate(raw_token, owner_type: "Player")
  end

  test "authenticate rejects expired keys" do
    player = create(:player)
    record, raw_token = ApiKey.generate_for(owner: player)
    record.update_columns(expires_at: 1.minute.ago)

    assert_nil ApiKey.authenticate(raw_token, owner_type: "Player")
  end
end
