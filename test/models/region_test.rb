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

  test "owner_kingdom_id follows an owned home-hoard node" do
    world = create(:world)
    region = create(:region, world: world)
    kingdom = create(:kingdom, world: world, home_region: region)
    create(:node, region: region, is_home_hoard: true, owner_kingdom_id: kingdom.id)

    assert_equal kingdom.id, region.reload.owner_kingdom_id
  end

  test "owner_kingdom_id is nil while the home-hoard is unowned, even if another node is captured" do
    world = create(:world)
    region = create(:region, world: world)
    kingdom = create(:kingdom, world: world, home_region: region)
    create(:node, region: region, is_home_hoard: true)
    create(:node, region: region, owner_kingdom_id: kingdom.id)

    assert_nil region.reload.owner_kingdom_id
  end

  test "owner_kingdom_id follows a single captured node in a non-home region" do
    world = create(:world)
    region = create(:region, world: world)
    kingdom = create(:kingdom, world: world)
    create(:node, region: region, owner_kingdom_id: kingdom.id)

    assert_equal kingdom.id, region.reload.owner_kingdom_id
  end

  test "owner_kingdom_id returns the shared owner when all nodes agree" do
    world = create(:world)
    region = create(:region, world: world)
    kingdom = create(:kingdom, world: world)
    create(:node, region: region, owner_kingdom_id: kingdom.id)
    create(:node, region: region, resource: "iron", owner_kingdom_id: kingdom.id)

    assert_equal kingdom.id, region.reload.owner_kingdom_id
  end

  test "owner_kingdom_id is nil for a contested region with nodes owned by different kingdoms" do
    world = create(:world)
    region = create(:region, world: world)
    a = create(:kingdom, world: world)
    b = create(:kingdom, world: world)
    create(:node, region: region, owner_kingdom_id: a.id)
    create(:node, region: region, resource: "iron", owner_kingdom_id: b.id)

    assert_nil region.reload.owner_kingdom_id
  end

  test "owner_kingdom_id is nil when no node is owned" do
    region = create(:region)
    create(:node, region: region)

    assert_nil region.reload.owner_kingdom_id
  end
end
