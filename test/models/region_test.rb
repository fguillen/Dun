require "test_helper"

class RegionTest < ActiveSupport::TestCase
  test "factory builds a valid region" do
    region = build(:region)
    assert region.valid?, region.errors.full_messages.join(", ")
  end

  test "terrain must be one of the allowed values" do
    region = build(:region, terrain: "tundra")
    assert_not region.valid?
  end

  test "name uniqueness scoped per world" do
    world = create(:world)
    create(:region, world: world, name: "Ironwood")
    dupe = build(:region, world: world, name: "Ironwood")
    assert_not dupe.valid?
  end

  test "same name allowed on different worlds" do
    create(:region, name: "Ironwood")
    twin = build(:region, name: "Ironwood")
    assert twin.valid?
  end

  test "adjacent_regions returns both directions of the adjacency table" do
    world = create(:world)
    a = create(:region, world: world)
    b = create(:region, world: world)
    c = create(:region, world: world)

    RegionAdjacency.connect(a, b)
    RegionAdjacency.connect(c, a)

    assert_equal [ b.id, c.id ].sort, a.adjacent_regions.pluck(:id).sort
  end

  test "x and y are read from position jsonb" do
    region = build(:region, position: { "x" => 0.25, "y" => 0.75 })
    assert_equal 0.25, region.x
    assert_equal 0.75, region.y
  end
end
