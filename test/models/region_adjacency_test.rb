require "test_helper"

class RegionAdjacencyTest < ActiveSupport::TestCase
  test "connect creates a canonical-ordered adjacency" do
    world = create(:world)
    a = create(:region, world: world)
    b = create(:region, world: world)

    adj = RegionAdjacency.connect(b, a)
    expected_lo, expected_hi = [ a.id, b.id ].sort
    assert_equal expected_lo, adj.region_a_id
    assert_equal expected_hi, adj.region_b_id
  end

  test "connect is idempotent regardless of argument order" do
    world = create(:world)
    a = create(:region, world: world)
    b = create(:region, world: world)

    first = RegionAdjacency.connect(a, b)
    second = RegionAdjacency.connect(b, a)
    assert_equal first.id, second.id
    assert_equal 1, RegionAdjacency.count
  end

  test "connected? returns true regardless of argument order" do
    world = create(:world)
    a = create(:region, world: world)
    b = create(:region, world: world)
    RegionAdjacency.connect(a, b)

    assert RegionAdjacency.connected?(a.id, b.id)
    assert RegionAdjacency.connected?(b.id, a.id)
    assert_not RegionAdjacency.connected?(a.id, a.id)
  end

  test "endpoints must be distinct" do
    world = create(:world)
    a = create(:region, world: world)
    adj = RegionAdjacency.new(region_a: a, region_b: a)
    assert_not adj.valid?
  end

  test "endpoints must share a world" do
    a = create(:region)
    b = create(:region)  # different world by default factory
    refute_equal a.world_id, b.world_id

    adj = RegionAdjacency.new(region_a: a, region_b: b)
    assert_not adj.valid?
    assert_includes adj.errors[:base], "endpoints must share a world"
  end
end
