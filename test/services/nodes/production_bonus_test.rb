require "test_helper"

module Nodes
  class ProductionBonusTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @home = create(:region, world: @world, name: "Home")
      @kingdom = create(:kingdom, world: @world, home_region: @home)
    end

    test "returns zero for every resource when no owned nodes" do
      bonuses = ProductionBonus.call(@kingdom)
      Kingdom::RESOURCES.each { |r| assert_equal 0, bonuses[r] }
    end

    test "sums by tier per resource (+120/+250/+500)" do
      r1 = create(:region, world: @world, name: "R1")
      r2 = create(:region, world: @world, name: "R2")
      r3 = create(:region, world: @world, name: "R3")
      r4 = create(:region, world: @world, name: "R4")

      create(:node, region: r1, resource: "gold", tier: "poor", base_rate: 120, owner_kingdom_id: @kingdom.id)
      create(:node, region: r2, resource: "gold", tier: "standard", base_rate: 250, owner_kingdom_id: @kingdom.id)
      create(:node, region: r3, resource: "stone", tier: "rich", base_rate: 500, owner_kingdom_id: @kingdom.id)
      # Unclaimed node should not contribute
      create(:node, region: r4, resource: "iron", tier: "rich", base_rate: 500)

      bonuses = ProductionBonus.call(@kingdom)
      assert_equal 370, bonuses["gold"]
      assert_equal 500, bonuses["stone"]
      assert_equal 0,   bonuses["iron"]
      assert_equal 0,   bonuses["wood"]
    end
  end
end
