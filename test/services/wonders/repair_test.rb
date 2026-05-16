require "test_helper"

module Wonders
  class RepairTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 17)
      @kingdom.update!(stockpiles: { "gold" => 0, "wood" => 0, "stone" => 20_000, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })
      @wonder = create(:wonder, kingdom: @kingdom, status: "construction", hp: 5_000)
    end

    test "spends 8 Stone per HP and bumps wonder.hp" do
      Repair.call(wonder: @wonder, hp: 100)
      @kingdom.reload
      assert_equal 20_000 - 800, @kingdom.stockpile("stone")
      assert_equal 5_100, @wonder.reload.hp
    end

    test "respects phase cap of 2000 HP" do
      @wonder.update!(repaired_hp_by_phase: { "foundation" => 0, "construction" => 2_000, "consecration" => 0 })
      assert_raises(Repair::CapReached) { Repair.call(wonder: @wonder, hp: 100) }
    end

    test "clamps to remaining phase cap" do
      @wonder.update!(repaired_hp_by_phase: { "foundation" => 0, "construction" => 1_950, "consecration" => 0 })
      Repair.call(wonder: @wonder, hp: 500)
      # only 50 HP could be repaired
      assert_equal 5_050, @wonder.reload.hp
      assert_equal 2_000, @wonder.reload.repaired_hp_by_phase["construction"]
    end

    test "pause adds 30 min per 500 HP repaired" do
      base = Time.current
      travel_to base do
        Repair.call(wonder: @wonder, hp: 500)
      end
      assert_in_delta base + 30.minutes, @wonder.reload.paused_until, 5
    end

    test "pause stacks when called twice" do
      base = Time.current
      travel_to base do
        Repair.call(wonder: @wonder, hp: 500)
        Repair.call(wonder: @wonder, hp: 500)
      end
      assert_in_delta base + 60.minutes, @wonder.reload.paused_until, 5
    end

    test "phase caps are independent across phases" do
      @wonder.update!(repaired_hp_by_phase: { "foundation" => 2_000, "construction" => 0, "consecration" => 0 })
      Repair.call(wonder: @wonder, hp: 100)
      assert_equal 5_100, @wonder.reload.hp
    end

    test "rejects when Wonder is destroyed" do
      @wonder.update!(status: "destroyed", hp: 0)
      assert_raises(Repair::NotRepairable) { Repair.call(wonder: @wonder, hp: 100) }
    end

    test "rejects when hp is non-positive" do
      assert_raises(Repair::InvalidAmount) { Repair.call(wonder: @wonder, hp: 0) }
      assert_raises(Repair::InvalidAmount) { Repair.call(wonder: @wonder, hp: -10) }
    end
  end
end
