require "test_helper"

class RuinTest < ActiveSupport::TestCase
  test "factory builds a valid ruin" do
    ruin = build(:ruin)
    assert ruin.valid?, ruin.errors.full_messages.join(", ")
  end

  test "tier inclusion is enforced" do
    bad = Ruin.new(region: create(:region), tier: "epic")
    assert_not bad.valid?
  end

  test "garrison table matches \u00a716.11" do
    assert_equal({ levy: 20, archer: 10 }, Ruin::GARRISONS["minor"])
    assert_equal({ levy: 40, archer: 20, pikeman: 10 }, Ruin::GARRISONS["standard"])
    assert_equal({ levy: 60, archer: 30, pikeman: 20, knight: 10 }, Ruin::GARRISONS["major"])
  end

  test "cache table matches \u00a716.11" do
    assert_equal({ gold: 4_000, wood: 4_000, stone: 2_000, iron: 4_000 }, Ruin::CACHES["minor"])
    assert_equal({ gold: 10_000, wood: 10_000, stone: 6_000, iron: 10_000 }, Ruin::CACHES["standard"])
    assert_equal({ gold: 25_000, wood: 25_000, stone: 15_000, iron: 25_000 }, Ruin::CACHES["major"])
  end

  test "claimed? reflects claimed_by_kingdom_id" do
    fresh = build(:ruin, claimed_by_kingdom_id: nil)
    assert_not fresh.claimed?

    fresh.claimed_by_kingdom_id = 1
    assert fresh.claimed?
  end
end
