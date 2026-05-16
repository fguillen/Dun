require "test_helper"

module Wonders
  class PayMilestoneTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @kingdom.buildings.find_by(kind: "warehouse").update!(level: 17)
      @kingdom.update!(stockpiles: {
        "gold" => 100_000, "wood" => 100_000, "stone" => 300_000, "iron" => 100_000,
        "checkpoint_at" => Time.current.iso8601
      })
      @wonder = create(:wonder,
        kingdom: @kingdom,
        status: "construction",
        hp: 2_500,
        pending_milestone_percent: 25
      )
    end

    test "deducts 10% milestone cost, clears pending, marks paid" do
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.wonder.milestone_paid") do
        PayMilestone.call(wonder: @wonder, percent: 25)
      end

      @wonder.reload
      assert_nil @wonder.pending_milestone_percent
      assert @wonder.milestones_paid_for?(25)

      @kingdom.reload
      assert_equal 20_000, @kingdom.stockpile("gold")    # 100_000 - 80_000
      assert_equal 40_000, @kingdom.stockpile("wood")    # 100_000 - 60_000
      assert_equal 60_000, @kingdom.stockpile("stone")   # 300_000 - 240_000
      assert_equal 20_000, @kingdom.stockpile("iron")    # 100_000 - 80_000

      assert_equal 1, events.size
      assert_equal 25, events.first[:percent]
    end

    test "advances last_construction_at so construction resumes from payment time" do
      old = 5.hours.ago
      @wonder.update!(last_construction_at: old)
      PayMilestone.call(wonder: @wonder, percent: 25)
      assert_operator @wonder.reload.last_construction_at, :>, old
    end

    test "rejects when no milestone pending" do
      @wonder.update!(pending_milestone_percent: nil)
      assert_raises(PayMilestone::NoMilestonePending) { PayMilestone.call(wonder: @wonder, percent: 25) }
    end

    test "rejects wrong percent" do
      assert_raises(PayMilestone::WrongPercent) { PayMilestone.call(wonder: @wonder, percent: 50) }
    end

    test "raises insufficient resources if stockpile too low" do
      @kingdom.update!(stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })
      assert_raises(Stockpile::Apply::InsufficientResources) { PayMilestone.call(wonder: @wonder, percent: 25) }
    end
  end
end
