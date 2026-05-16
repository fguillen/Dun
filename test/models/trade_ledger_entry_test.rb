require "test_helper"

class TradeLedgerEntryTest < ActiveSupport::TestCase
  test "ULID id assigned on create" do
    entry = create(:trade_ledger_entry)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, entry.id)
  end

  test "rejects unknown resource" do
    entry = build(:trade_ledger_entry, resource: "magic")
    refute entry.valid?
    assert entry.errors[:resource].present?
  end

  test "rejects unknown status" do
    entry = build(:trade_ledger_entry, status: "rerouted")
    refute entry.valid?
    assert entry.errors[:status].present?
  end

  test "rejects negative amount" do
    entry = build(:trade_ledger_entry, amount: -1)
    refute entry.valid?
    assert entry.errors[:amount].present?
  end

  test "for_handle scope matches sender, receiver, or attacker" do
    a = create(:trade_ledger_entry, sender_handle_at_send: "Alice")
    b = create(:trade_ledger_entry, receiver_handle_at_send: "Alice")
    c = create(:trade_ledger_entry, attacker_handle: "Alice", status: "intercepted")
    d = create(:trade_ledger_entry, sender_handle_at_send: "Bob")

    found = TradeLedgerEntry.for_handle("Alice")
    assert_includes found, a
    assert_includes found, b
    assert_includes found, c
    refute_includes found, d
  end

  test "since scope filters by recorded_at" do
    old   = create(:trade_ledger_entry, recorded_at: 3.days.ago)
    fresh = create(:trade_ledger_entry, recorded_at: 1.hour.ago)

    found = TradeLedgerEntry.since(1.day.ago)
    refute_includes found, old
    assert_includes found, fresh
  end

  test "newest_first orders by recorded_at desc" do
    old   = create(:trade_ledger_entry, recorded_at: 3.days.ago)
    new_  = create(:trade_ledger_entry, recorded_at: 1.hour.ago)

    assert_equal [ new_.id, old.id ], TradeLedgerEntry.newest_first.pluck(:id)
  end
end
