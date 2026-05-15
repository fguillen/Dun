require "test_helper"

class MarchOrderTest < ActiveSupport::TestCase
  test "ULID id is assigned on create" do
    order = create(:march_order)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, order.id)
  end

  test "validates intent is in INTENTS whitelist" do
    order = build(:march_order, intent: "siege")
    refute order.valid?
    assert order.errors[:intent].present?
  end

  test "rejects path that does not start at origin" do
    army = create(:army)
    target = create(:region, world: army.kingdom.world)
    bogus = create(:region, world: army.kingdom.world)
    order = build(:march_order,
      army: army,
      origin_region: army.location_region,
      target_region: target,
      path: [ bogus.id, target.id ])
    refute order.valid?
    assert order.errors[:path].present?
  end

  test "rejects path that does not end at target" do
    army = create(:army)
    target = create(:region, world: army.kingdom.world)
    bogus = create(:region, world: army.kingdom.world)
    order = build(:march_order,
      army: army,
      origin_region: army.location_region,
      target_region: target,
      path: [ army.location_region.id, bogus.id ])
    refute order.valid?
    assert order.errors[:path].present?
  end

  test "active scope excludes arrived and recalled orders" do
    open     = create(:march_order)
    arrived  = create(:march_order, arrived_at: Time.current)
    recalled = create(:march_order, recalled_at: Time.current)

    active = MarchOrder.active
    assert_includes active, open
    refute_includes active, arrived
    refute_includes active, recalled
  end

  test "ripe returns active orders past arrives_at" do
    past   = create(:march_order, arrives_at: 1.minute.ago)
    future = create(:march_order, arrives_at: 1.minute.from_now)

    ripe = MarchOrder.ripe.to_a
    assert_includes ripe, past
    refute_includes ripe, future
  end

  test "active? + resolved? reflect arrival or recall" do
    order = create(:march_order)
    assert order.active?
    refute order.resolved?

    order.update!(arrived_at: Time.current)
    refute order.active?
    assert order.resolved?
  end
end
