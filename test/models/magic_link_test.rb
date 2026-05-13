require "test_helper"

class MagicLinkTest < ActiveSupport::TestCase
  test "generate_for stores only the digest and returns the raw token once" do
    record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

    assert_not_nil raw_token
    assert_not_equal raw_token, record.token_digest
    assert_equal Digest::SHA256.hexdigest(raw_token), record.token_digest
    assert record.expires_at > 14.minutes.from_now
    assert record.expires_at < 16.minutes.from_now
    assert_nil record.consumed_at
    assert_nil record.owner_id
  end

  test "generate_for rejects unknown owner_type" do
    assert_raises(ArgumentError) { MagicLink.generate_for(owner_type: "Hacker", email: "x@example.com") }
  end

  test "find_by_token resolves by digest" do
    record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

    assert_equal record, MagicLink.find_by_token(raw_token)
    assert_nil MagicLink.find_by_token("garbage")
    assert_nil MagicLink.find_by_token(nil)
  end

  test "consume! sets owner + consumed_at, rejects double-consume" do
    record, _raw = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")
    player = create(:player, email: "alice@example.com")

    record.consume!(owner: player)

    assert_equal player, record.reload.owner
    assert record.consumed_at.present?

    assert_raises(MagicLink::AlreadyConsumed) { record.consume!(owner: player) }
  end

  test "consume! raises Expired past 15 minutes" do
    record, _raw = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")
    record.update_columns(expires_at: 1.minute.ago)
    player = create(:player, email: "alice@example.com")

    assert_raises(MagicLink::Expired) { record.consume!(owner: player) }
  end

  test "consume! rejects an owner of the wrong type" do
    record, _raw = MagicLink.generate_for(owner_type: "Player", email: "x@example.com")
    admin = create(:admin, email: "x@example.com")

    assert_raises(ArgumentError) { record.consume!(owner: admin) }
  end
end
