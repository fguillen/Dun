require "test_helper"

class NodeTest < ActiveSupport::TestCase
  test "factory builds a valid node" do
    node = build(:node)
    assert node.valid?, node.errors.full_messages.join(", ")
  end

  test "resource and tier inclusion is enforced" do
    region = create(:region)
    bad = Node.new(region: region, resource: "platinum", tier: "rich", base_rate: 500)
    assert_not bad.valid?
    assert_includes bad.errors[:resource], "is not included in the list"
  end

  test "tier base rates match \u00a716.5 table" do
    assert_equal 120, Node::TIER_BASE_RATE["poor"]
    assert_equal 250, Node::TIER_BASE_RATE["standard"]
    assert_equal 500, Node::TIER_BASE_RATE["rich"]
  end

  test "wilderness garrisons match \u00a716.5 table" do
    assert_equal({ levy: 15, archer: 5 }, Node::WILDERNESS_GARRISONS["poor"])
    assert_equal({ levy: 25, archer: 10, pikeman: 5 }, Node::WILDERNESS_GARRISONS["standard"])
    assert_equal({ levy: 40, archer: 20, pikeman: 15, knight: 5 }, Node::WILDERNESS_GARRISONS["rich"])
  end

  test "wilderness? true when no owner" do
    node = build(:node, owner_kingdom_id: nil)
    assert node.wilderness?
  end

  test "claimed scope returns only owned nodes" do
    create(:node, owner_kingdom_id: nil)
    owned = create(:node, owner_kingdom_id: 42)
    assert_equal [ owned ], Node.claimed
  end
end
