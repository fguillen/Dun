require "test_helper"

module Production
  class RateForTest < ActiveSupport::TestCase
    test "rate = base * building level" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "quarry").update!(level: 5)
      assert_equal 25 * 5, RateFor.call(kingdom: kingdom, resource: "stone")
    end

    test "rate adds owned node bonuses for matching resource only" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "gold_mint").update!(level: 3)
      region = kingdom.world.regions.first || create(:region, world: kingdom.world)
      create(:node, region: region, resource: "gold",  tier: "rich",     base_rate: 500, owner_kingdom_id: kingdom.id)
      create(:node, region: region, resource: "gold",  tier: "standard", base_rate: 250, owner_kingdom_id: kingdom.id)
      create(:node, region: region, resource: "stone", tier: "standard", base_rate: 250, owner_kingdom_id: kingdom.id)

      assert_equal (30 * 3) + 500 + 250, RateFor.call(kingdom: kingdom, resource: "gold")
    end

    test "no production building => only node bonus" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "iron_mine").update!(level: 0)
      region = kingdom.world.regions.first || create(:region, world: kingdom.world)
      create(:node, region: region, resource: "iron", tier: "poor", base_rate: 120, owner_kingdom_id: kingdom.id)
      assert_equal 120, RateFor.call(kingdom: kingdom, resource: "iron")
    end

    test "unknown resource raises" do
      kingdom = create(:kingdom, :with_buildings)
      assert_raises(ArgumentError) { RateFor.call(kingdom: kingdom, resource: "mana") }
    end
  end
end
