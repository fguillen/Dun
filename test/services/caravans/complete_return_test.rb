require "test_helper"

module Caravans
  class CompleteReturnTest < ActiveSupport::TestCase
    setup do
      @server = create(:server)
      @world  = create(:world, :active, server: @server)

      @origin = create(:region, world: @world, terrain: "plains", name: "OriginHome")
      @dest   = create(:region, world: @world, terrain: "plains", name: "DestHome")
      RegionAdjacency.connect(@origin, @dest)

      @sender_profile   = create(:player_profile, server: @server, handle: "Alice")
      @receiver_profile = create(:player_profile, server: @server, handle: "Bob")

      @sender = create(:kingdom, :with_buildings,
        world: @world, player_profile: @sender_profile, home_region: @origin,
        stockpiles: { "gold" => 1_000, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })
      @receiver = create(:kingdom, :with_buildings,
        world: @world, player_profile: @receiver_profile, home_region: @dest,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })

      @source_army = create(:army, kingdom: @sender, location_region: @origin,
        name: "Sender Home Army", composition: { "knight" => 10 })
    end

    def dispatch_and_deliver
      caravan = Caravans::Dispatch.call(
        sender_kingdom: @sender, receiver_kingdom: @receiver,
        source_army: @source_army,
        payload: { "gold" => 200 }, escort_units: { "knight" => 5 })
      Caravans::Deliver.call(caravan: caravan)
      caravan.reload
    end

    test "merges escort survivors back into sender's home army at origin" do
      caravan = dispatch_and_deliver
      # @source_army (still at @origin with knight=5) is the merge target.
      escort_id = caravan.escort_army_id

      CompleteReturn.call(caravan: caravan)

      @source_army.reload
      assert_equal({ "knight" => 10 }, @source_army.composition)
      refute Army.exists?(escort_id)
      caravan.reload
      # outbound + return MarchOrders were destroyed as part of escort_army cascade
      # (and FK to caravan nullified). escort_army_id may still equal nil now.
    end

    test "converts escort to a home army when sender has no other army at origin" do
      caravan = dispatch_and_deliver
      # Destroy the source army so there's no merge target at origin.
      @source_army.destroy!

      CompleteReturn.call(caravan: caravan)

      remaining = @sender.armies.where(location_region_id: @origin.id).to_a
      assert_equal 1, remaining.size
      assert_equal "home", remaining.first.status
      assert_equal({ "knight" => 5 }, remaining.first.composition)
    end

    test "emits dun.caravan.returned" do
      caravan = dispatch_and_deliver
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.caravan.returned") do
        CompleteReturn.call(caravan: caravan)
      end
      assert_equal 1, events.size
      assert_equal caravan.id, events.first[:caravan_id]
    end
  end
end
