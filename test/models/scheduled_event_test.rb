require "test_helper"

class ScheduledEventTest < ActiveSupport::TestCase
  test "ULID id is assigned on create" do
    event = create(:scheduled_event)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, event.id)
  end

  test "kind must be in the whitelist" do
    event = build(:scheduled_event, kind: "fictional_kind")
    refute event.valid?
    assert event.errors[:kind].present?
  end

  test "pending scope excludes processed rows" do
    pending = create(:scheduled_event, fire_at: 1.minute.ago)
    processed = create(:scheduled_event, fire_at: 1.minute.ago, processed_at: Time.current)

    assert_includes ScheduledEvent.pending, pending
    refute_includes ScheduledEvent.pending, processed
  end

  test "ripe returns only pending events whose fire_at has passed" do
    past = create(:scheduled_event, fire_at: 1.minute.ago)
    future = create(:scheduled_event, fire_at: 1.minute.from_now)

    ripe = ScheduledEvent.ripe.to_a
    assert_includes ripe, past
    refute_includes ripe, future
  end

  test "two events at identical fire_at are deterministically ordered by id (ULID is monotonic)" do
    fire_at = 1.minute.ago
    first  = create(:scheduled_event, fire_at: fire_at)
    second = create(:scheduled_event, fire_at: fire_at)

    ordered_ids = ScheduledEvent.ripe.order(:fire_at, :id).pluck(:id)
    assert_equal [ first.id, second.id ], ordered_ids
  end
end
