require "test_helper"

module Caravans
  class DeliverTest < ActiveSupport::TestCase
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
        composition: { "knight" => 10 })
    end

    def dispatch_caravan(payload: { "gold" => 200 }, escort_units: { "knight" => 5 })
      Caravans::Dispatch.call(
        sender_kingdom: @sender,
        receiver_kingdom: @receiver,
        source_army: @source_army,
        payload: payload,
        escort_units: escort_units
      )
    end

    test "credits payload to receiver, flips ledger, schedules return march" do
      caravan = dispatch_caravan

      Deliver.call(caravan: caravan)

      caravan.reload
      assert_equal "delivered", caravan.status
      assert_not_nil caravan.delivered_at

      receiver_state = Stockpile::Read.call(@receiver.reload)
      assert_equal 200, receiver_state["gold"]

      assert caravan.ledger_entries.all? { |e| e.status == "delivered" }

      return_order = caravan.return_march_order
      assert return_order
      assert_equal "caravan_return", return_order.intent
      assert_equal @dest.id, return_order.origin_region_id
      assert_equal @origin.id, return_order.target_region_id
      assert_equal [ @dest.id, @origin.id ], return_order.path
      assert_equal "returning", caravan.escort_army.reload.status

      event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", return_order.id)
        .first
      assert event
    end

    test "warehouse cap silently drops excess" do
      cap = Buildings::Catalog.warehouse_cap(@receiver.buildings.find_by(kind: "warehouse").level)
      # Pre-fill receiver so a 400 delivery would push past the cap.
      @receiver.update!(stockpiles: { "gold" => cap - 50, "wood" => 0, "stone" => 0, "iron" => 0,
                                       "checkpoint_at" => Time.current.iso8601 })

      # 5 knights = 400 capacity; payload 400 gold fits.
      caravan = dispatch_caravan(payload: { "gold" => 400 }, escort_units: { "knight" => 5 })

      Deliver.call(caravan: caravan)
      receiver_state = Stockpile::Read.call(@receiver.reload)
      assert_equal cap, receiver_state["gold"]
    end

    test "idempotent: second Deliver on the same caravan is a no-op" do
      caravan = dispatch_caravan
      Deliver.call(caravan: caravan)
      receiver_after_first = Stockpile::Read.call(@receiver.reload)["gold"]
      Deliver.call(caravan: caravan)
      receiver_after_second = Stockpile::Read.call(@receiver.reload)["gold"]
      assert_equal receiver_after_first, receiver_after_second
    end

    test "emits dun.caravan.delivered" do
      caravan = dispatch_caravan
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.caravan.delivered") do
        Deliver.call(caravan: caravan)
      end
      assert_equal 1, events.size
      assert_equal caravan.id, events.first[:caravan_id]
    end
  end
end
