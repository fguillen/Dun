require "test_helper"

class ArmyTest < ActiveSupport::TestCase
  test "ULID id is assigned on create" do
    army = create(:army)
    assert_match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/, army.id)
  end

  test "validates name presence and status whitelist" do
    army = build(:army, name: "")
    refute army.valid?
    assert army.errors[:name].present?

    army = build(:army, status: "fleeing")
    refute army.valid?
    assert army.errors[:status].present?
  end

  test "rejects unknown unit kinds in composition" do
    army = build(:army, composition: { "ninja" => 5 })
    refute army.valid?
    assert army.errors[:composition].present?
  end

  test "rejects negative counts in composition" do
    army = build(:army, composition: { "levy" => -3 })
    refute army.valid?
    assert army.errors[:composition].present?
  end

  test "name is unique within a kingdom" do
    first = create(:army, name: "Strike Force")
    duplicate = build(:army, kingdom: first.kingdom, location_region: first.location_region, name: "Strike Force")
    refute duplicate.valid?
  end

  test "empty? reflects total unit count" do
    assert build(:army, composition: {}).empty?
    assert build(:army, composition: { "levy" => 0 }).empty?
    refute build(:army, composition: { "levy" => 1 }).empty?
  end

  test "total_capacity sums unit capacities (TODO §16.3 capacity sum)" do
    army = build(:army, composition: { "levy" => 10, "knight" => 5 })
    assert_equal 10 * 50 + 5 * 80, army.total_capacity
  end

  test "slowest_speed returns the minimum unit speed in the composition" do
    army = build(:army, composition: { "knight" => 1, "levy" => 1, "trebuchet" => 1 })
    assert_equal 0.2, army.slowest_speed

    knight_only = build(:army, composition: { "knight" => 1 })
    assert_equal 1.0, knight_only.slowest_speed
  end

  test "all_terrain_immune? requires every present unit to be Knight or Scout" do
    assert build(:army, composition: { "knight" => 5, "scout" => 2 }).all_terrain_immune?
    refute build(:army, composition: { "knight" => 5, "levy" => 1 }).all_terrain_immune?
    refute build(:army, composition: {}).all_terrain_immune?
  end

  test "garrison? matches the canonical garrison name" do
    assert build(:army, name: "Garrison").garrison?
    refute build(:army, name: "Strike Force").garrison?
  end

  test "status scopes filter by status" do
    home      = create(:army, status: "home")
    marching  = create(:army, status: "marching")
    engaged   = create(:army, status: "engaged")
    returning = create(:army, status: "returning")

    assert_includes Army.home,      home
    assert_includes Army.marching,  marching
    assert_includes Army.engaged,   engaged
    assert_includes Army.returning, returning
  end
end
