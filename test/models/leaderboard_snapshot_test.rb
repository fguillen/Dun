require "test_helper"

class LeaderboardSnapshotTest < ActiveSupport::TestCase
  setup do
    @server = create(:server)
  end

  test "rejects unknown kinds" do
    snap = LeaderboardSnapshot.new(server: @server, kind: "bogus", snapshot_at: Time.current)
    refute snap.valid?
    assert_includes snap.errors[:kind], "is not included in the list"
  end

  test "enforces uniqueness per kind per server" do
    LeaderboardSnapshot.create!(server: @server, kind: "champions", snapshot_at: Time.current, entries: [])
    assert_raises(ActiveRecord::RecordNotUnique) do
      LeaderboardSnapshot.create!(server: @server, kind: "champions", snapshot_at: Time.current, entries: [])
    end
  end
end
