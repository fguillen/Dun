require "test_helper"

class CaravanTest < ActiveSupport::TestCase
  test "ULID id assigned on create" do
    caravan = create(:caravan)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, caravan.id)
  end

  test "rejects unknown status" do
    caravan = build(:caravan, status: "in_orbit")
    refute caravan.valid?
    assert caravan.errors[:status].present?
  end

  test "rejects payload with unknown resource" do
    caravan = build(:caravan, payload: { "magic" => 100 })
    refute caravan.valid?
    assert caravan.errors[:payload].present?
  end

  test "rejects payload with negative amount" do
    caravan = build(:caravan, payload: { "gold" => -10 })
    refute caravan.valid?
    assert caravan.errors[:payload].present?
  end

  test "rejects empty payload" do
    caravan = build(:caravan, payload: { "gold" => 0, "wood" => 0 })
    refute caravan.valid?
    assert caravan.errors[:payload].present?
  end

  test "rejects escort_units with unknown unit" do
    caravan = build(:caravan, escort_units: { "dragon" => 1 })
    refute caravan.valid?
    assert caravan.errors[:escort_units].present?
  end

  test "rejects empty escort_units" do
    caravan = build(:caravan, escort_units: { "levy" => 0 })
    refute caravan.valid?
    assert caravan.errors[:escort_units].present?
  end

  test "status predicates" do
    in_transit  = build(:caravan, status: "in_transit")
    delivered   = build(:caravan, status: "delivered")
    intercepted = build(:caravan, status: "intercepted")

    assert in_transit.in_transit?
    assert delivered.delivered?
    assert intercepted.intercepted?
    refute delivered.in_transit?
  end

  test "scopes select by status" do
    a = create(:caravan, status: "in_transit")
    b = create(:caravan, status: "delivered")
    c = create(:caravan, status: "intercepted")

    assert_includes Caravan.in_transit, a
    refute_includes Caravan.in_transit, b
    assert_includes Caravan.delivered, b
    assert_includes Caravan.intercepted, c
  end
end
