require "test_helper"

class TrainingOrderTest < ActiveSupport::TestCase
  test "ULID id is assigned on create" do
    order = create(:training_order)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, order.id)
  end

  test "validates unit is in Units::Catalog::KINDS" do
    order = build(:training_order, unit: "ninja")
    refute order.valid?
    assert order.errors[:unit].present?
  end

  test "validates building_kind is one of the three military buildings" do
    order = build(:training_order, building_kind: "warehouse")
    refute order.valid?
    assert order.errors[:building_kind].present?
  end

  test "validates count > 0" do
    order = build(:training_order, count: 0)
    refute order.valid?
    assert order.errors[:count].present?
  end

  test "rejects unit/building mismatch (e.g. levy at stable)" do
    order = build(:training_order, building_kind: "stable", unit: "levy")
    refute order.valid?
    assert order.errors[:unit].present?
  end

  test "in_progress excludes cancelled and completed orders" do
    open      = create(:training_order)
    cancelled = create(:training_order, cancelled_at: Time.current)
    completed = create(:training_order, completed_at: Time.current)

    in_progress = TrainingOrder.in_progress
    assert_includes in_progress, open
    refute_includes in_progress, cancelled
    refute_includes in_progress, completed
  end

  test "ripe returns in-progress orders past completes_at" do
    past   = create(:training_order, completes_at: 1.minute.ago)
    future = create(:training_order, completes_at: 1.minute.from_now)

    ripe = TrainingOrder.ripe.to_a
    assert_includes ripe, past
    refute_includes ripe, future
  end

  test "in_progress? + resolved? mirror cancellation/completion state" do
    order = create(:training_order)
    assert order.in_progress?
    refute order.resolved?

    order.update!(cancelled_at: Time.current)
    refute order.in_progress?
    assert order.resolved?
  end
end
