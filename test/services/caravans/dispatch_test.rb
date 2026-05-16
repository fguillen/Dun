require "test_helper"

module Caravans
  class DispatchTest < ActiveSupport::TestCase
    setup do
      @server = create(:server)
      @world  = create(:world, :active, server: @server)

      @sender_region   = create(:region, world: @world, terrain: "plains", name: "Sender Home")
      @receiver_region = create(:region, world: @world, terrain: "plains", name: "Receiver Home")
      RegionAdjacency.connect(@sender_region, @receiver_region)

      @sender_profile   = create(:player_profile, server: @server, handle: "Alice")
      @receiver_profile = create(:player_profile, server: @server, handle: "Bob")

      @sender = create(:kingdom, world: @world, player_profile: @sender_profile, home_region: @sender_region,
        stockpiles: { "gold" => 1_000, "wood" => 500, "stone" => 0, "iron" => 0 })
      @receiver = create(:kingdom, world: @world, player_profile: @receiver_profile, home_region: @receiver_region,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 })

      # Sender needs a warehouse so Stockpile::Apply has a cap. The Stockpile::Apply
      # service treats missing warehouse as level 0 — but Buildings::Catalog must
      # answer warehouse_cap(0). Confirm via existing convention.
      @source_army = create(:army,
        kingdom: @sender,
        location_region: @sender_region,
        composition: { "knight" => 10 }) # capacity 80 * 10 = 800
    end

    test "creates caravan, deducts stockpile, dispatches escort march, writes ledger" do
      caravan = Dispatch.call(
        sender_kingdom: @sender,
        receiver_kingdom: @receiver,
        source_army: @source_army,
        payload: { "gold" => 200, "wood" => 100 },
        escort_units: { "knight" => 5 }
      )

      assert_equal "in_transit", caravan.status
      assert_equal @world.id, caravan.world_id
      assert_equal @sender.id, caravan.sender_kingdom_id
      assert_equal @receiver.id, caravan.receiver_kingdom_id
      assert_equal({ "gold" => 200, "wood" => 100 }, caravan.payload)
      assert_equal({ "knight" => 5 }, caravan.escort_units)
      assert caravan.outbound_march_order
      assert_equal "caravan", caravan.outbound_march_order.intent

      escort = caravan.escort_army
      assert_equal "marching", escort.reload.status
      assert_equal({ "knight" => 5 }, escort.composition)

      @source_army.reload
      assert_equal({ "knight" => 5 }, @source_army.composition)

      sender_state = Stockpile::Read.call(@sender.reload)
      assert_equal 800, sender_state["gold"]
      assert_equal 400, sender_state["wood"]

      ledger = caravan.ledger_entries.order(:resource)
      assert_equal %w[gold wood], ledger.map(&:resource)
      assert_equal [ 200, 100 ], ledger.map(&:amount)
      assert ledger.all? { |e| e.status == "in_transit" }
      assert ledger.all? { |e| e.sender_handle_at_send == "Alice" }
      assert ledger.all? { |e| e.receiver_handle_at_send == "Bob" }
    end

    test "rejects cross-world receiver" do
      other_world = create(:world, :active, server: @server)
      other_region = create(:region, world: other_world)
      other_profile = create(:player_profile, server: @server, handle: "Charlie")
      other_kingdom = create(:kingdom, world: other_world, player_profile: other_profile, home_region: other_region)

      assert_raises(Dispatch::CrossWorld) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: other_kingdom,
          source_army: @source_army,
          payload: { "gold" => 100 },
          escort_units: { "knight" => 5 }
        )
      end
    end

    test "rejects self-trade" do
      assert_raises(Dispatch::SelfTrade) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @sender,
          source_army: @source_army,
          payload: { "gold" => 100 },
          escort_units: { "knight" => 5 }
        )
      end
    end

    test "rejects eliminated receiver" do
      @receiver.update!(eliminated_at: 1.hour.ago)
      assert_raises(Dispatch::ReceiverEliminated) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @receiver,
          source_army: @source_army,
          payload: { "gold" => 100 },
          escort_units: { "knight" => 5 }
        )
      end
    end

    test "rejects payload exceeding escort capacity" do
      # 1 knight = 80 capacity; payload 200 wood + 200 gold = 400 > 80
      assert_raises(Dispatch::InsufficientCapacity) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @receiver,
          source_army: @source_army,
          payload: { "gold" => 200, "wood" => 200 },
          escort_units: { "knight" => 1 }
        )
      end
    end

    test "rejects empty payload" do
      assert_raises(Dispatch::InvalidPayload) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @receiver,
          source_army: @source_army,
          payload: { "gold" => 0 },
          escort_units: { "knight" => 5 }
        )
      end
    end

    test "rejects when sender stockpile insufficient" do
      # 10 knights -> 800 capacity, room to ship 800 gold. Sender only has 1000 gold and walls don't apply,
      # but we ask for more than the stockpile -> Stockpile::Apply raises first.
      @sender.update!(stockpiles: { "gold" => 100, "wood" => 0, "stone" => 0, "iron" => 0,
                                     "checkpoint_at" => Time.current.iso8601 })
      assert_raises(Stockpile::Apply::InsufficientResources) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @receiver,
          source_army: @source_army,
          payload: { "gold" => 500 },
          escort_units: { "knight" => 10 }
        )
      end
      # state unchanged
      assert_equal({ "knight" => 10 }, @source_army.reload.composition)
    end

    test "rejects when source army lacks escort units" do
      assert_raises(Armies::Split::InsufficientUnits) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @receiver,
          source_army: @source_army,
          payload: { "gold" => 100 },
          escort_units: { "knight" => 50 }
        )
      end
    end

    test "rolls back stockpile deduction on later failure" do
      # Stub Marches::Dispatch to raise after stockpile is deducted
      Marches::Dispatch.stubs(:call).raises(StandardError, "boom")

      original_gold = Stockpile::Read.call(@sender)["gold"]

      assert_raises(StandardError) do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @receiver,
          source_army: @source_army,
          payload: { "gold" => 200 },
          escort_units: { "knight" => 5 }
        )
      end

      assert_equal original_gold, Stockpile::Read.call(@sender.reload)["gold"]
      assert_equal({ "knight" => 10 }, @source_army.reload.composition)
    end

    test "emits dun.caravan.dispatched" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }
      ActiveSupport::Notifications.subscribed(callback, "dun.caravan.dispatched") do
        Dispatch.call(
          sender_kingdom: @sender,
          receiver_kingdom: @receiver,
          source_army: @source_army,
          payload: { "gold" => 100 },
          escort_units: { "knight" => 5 }
        )
      end

      assert_equal 1, events.size
      assert_equal @sender.id, events.first[:sender_kingdom_id]
      assert_equal @receiver.id, events.first[:receiver_kingdom_id]
    end
  end
end
