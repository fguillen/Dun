require "test_helper"

module Ruins
  class ClaimTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @home = create(:region, world: @world, terrain: "plains", name: "Home")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@home, @target)

      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @home)
      @kingdom.update!(stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })
    end

    def dispatch(army)
      order = Marches::Dispatch.call(army: army, target_region: @target, intent: "claim_ruin")
      order.update!(arrives_at: 1.minute.ago)
      order
    end

    test "on victory grants the cache, claims the ruin, emits dun.ruin.claimed" do
      ruin = create(:ruin, region: @target, garrison: { "levy" => 1 }, cache: { "gold" => 100, "wood" => 0, "stone" => 0, "iron" => 0 })
      army = create(:army, kingdom: @kingdom, location_region: @home,
        composition: { "knight" => 100 })
      order = dispatch(army)

      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.ruin.claimed") do
        Claim.call(march_order: order, ruin: ruin, rng: Random.new(7))
      end

      ruin.reload
      assert ruin.claimed?
      assert_equal @kingdom.id, ruin.claimed_by_kingdom_id
      assert_not_nil ruin.claimed_at
      assert_equal 1, events.size
      assert_equal({ "gold" => 100, "wood" => 0, "stone" => 0, "iron" => 0 }, events.first[:granted])
      assert_equal 100, @kingdom.reload.stockpile("gold")
    end

    test "excess cache is dropped at the warehouse cap (no exception)" do
      # warehouse level 0 → cap 5000. Major cache is 25k gold → 20k+ lost.
      ruin = create(:ruin, :major, region: @target, garrison: { "levy" => 1 })
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "knight" => 200 })
      order = dispatch(army)

      battle = Claim.call(march_order: order, ruin: ruin, rng: Random.new(11))
      assert ruin.reload.claimed?

      # Granted gold should be capped at the warehouse cap (5000), not 25000.
      assert_operator battle.loot["gold"].to_i, :<=, 5_000
      assert_equal 5_000, @kingdom.reload.stockpile("gold")
    end

    test "on loss the ruin remains unclaimed" do
      ruin = create(:ruin, :major, region: @target)
      army = create(:army, kingdom: @kingdom, location_region: @home,
        composition: { "levy" => 1 })
      order = dispatch(army)

      Claim.call(march_order: order, ruin: ruin, rng: Random.new(1))

      ruin.reload
      refute ruin.claimed?
    end

    test "raises AlreadyClaimed when the ruin is already claimed" do
      other = create(:kingdom, world: @world, home_region: create(:region, world: @world, name: "Other"))
      ruin = create(:ruin, region: @target, claimed_by_kingdom_id: other.id, claimed_at: 1.day.ago)
      army = create(:army, kingdom: @kingdom, location_region: @home, composition: { "knight" => 10 })
      order = dispatch(army)
      assert_raises(Claim::AlreadyClaimed) do
        Claim.call(march_order: order, ruin: ruin, rng: Random.new(1))
      end
    end
  end
end
