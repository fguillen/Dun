require "test_helper"

module Wonders
  class PrerequisitesTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      fund_for_foundation
      raise_levels_to_prereqs
      grant_three_nodes
    end

    test "passes when all prereqs are met" do
      assert Prerequisites.call(kingdom: @kingdom)
    end

    test "fails when world is not active" do
      @world.update!(status: "grace")
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "world_not_active", err.reason
    end

    test "fails when kingdom eliminated" do
      @kingdom.update!(eliminated_at: 1.day.ago)
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "kingdom_eliminated", err.reason
    end

    test "fails when town_hall < 10" do
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 9)
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "need_town_hall_level_10", err.reason
    end

    test "fails when quarry < 10" do
      @kingdom.buildings.find_by(kind: "quarry").update!(level: 9)
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "need_quarry_level_10", err.reason
    end

    test "fails when siege_workshop < 5" do
      @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 4)
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "need_siege_workshop_level_5", err.reason
    end

    test "fails with fewer than 3 nodes" do
      Node.where(owner_kingdom_id: @kingdom.id).first.update!(owner_kingdom_id: nil)
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "need_3_nodes", err.reason
    end

    test "fails when a live Wonder already exists" do
      create(:wonder, kingdom: @kingdom)
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "wonder_already_active", err.reason
    end

    test "fails when stockpile cannot afford foundation cost" do
      @kingdom.update!(stockpiles: zero_stockpiles)
      err = assert_raises(Prerequisites::NotMet) { Prerequisites.call(kingdom: @kingdom) }
      assert_equal "insufficient_resources", err.reason
    end

    private

    def fund_for_foundation
      @kingdom.update!(stockpiles: {
        "gold" => 300_000, "wood" => 300_000, "stone" => 700_000, "iron" => 300_000,
        "checkpoint_at" => Time.current.iso8601
      })
      # Bump warehouse cap to fit prepay funds: cap = 5000 + 2500*L^2; L=17 → ~727500.
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 17)
    end

    def zero_stockpiles
      { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 }
    end

    def raise_levels_to_prereqs
      @kingdom.buildings.find_by(kind: "town_hall").update!(level: 10)
      @kingdom.buildings.find_by(kind: "quarry").update!(level: 10)
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 5)
      @kingdom.buildings.find_by(kind: "iron_mine").update!(level: 5)
      @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 5)
    end

    def grant_three_nodes
      3.times do |i|
        region = create(:region, world: @world, name: "node-#{i}")
        create(:node, region: region, owner_kingdom_id: @kingdom.id)
      end
    end
  end
end
