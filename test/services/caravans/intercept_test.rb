require "test_helper"

module Caravans
  class InterceptTest < ActiveSupport::TestCase
    setup do
      @server = create(:server)
      @world  = create(:world, :active, server: @server)

      @origin = create(:region, world: @world, terrain: "plains", name: "OriginHome")
      @dest   = create(:region, world: @world, terrain: "plains", name: "DestHome")
      RegionAdjacency.connect(@origin, @dest)

      @sender_profile     = create(:player_profile, server: @server, handle: "Alice")
      @receiver_profile   = create(:player_profile, server: @server, handle: "Bob")
      @hostile_profile    = create(:player_profile, server: @server, handle: "Eve")

      @sender = create(:kingdom, :with_buildings,
        world: @world, player_profile: @sender_profile, home_region: @origin,
        stockpiles: { "gold" => 2_000, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })
      @receiver = create(:kingdom, :with_buildings,
        world: @world, player_profile: @receiver_profile, home_region: @dest,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })
      @hostile_home = create(:region, world: @world, terrain: "plains", name: "HostileHome")
      @hostile = create(:kingdom, :with_buildings,
        world: @world, player_profile: @hostile_profile, home_region: @hostile_home,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })

      @source_army = create(:army, kingdom: @sender, location_region: @origin,
        composition: { "knight" => 10 })
    end

    def dispatch_caravan(payload: { "gold" => 400 }, escort_units: { "knight" => 5 })
      Caravans::Dispatch.call(
        sender_kingdom: @sender, receiver_kingdom: @receiver,
        source_army: @source_army, payload: payload, escort_units: escort_units
      )
    end

    test "escort loses → cargo transfers to hostile (capped by capacity then warehouse)" do
      caravan = dispatch_caravan(payload: { "gold" => 400 }, escort_units: { "knight" => 5 })
      # Tiny escort vs massive hostile — escort loses outright.
      caravan.escort_army.update!(composition: { "scout" => 1 })

      hostile_army = create(:army, kingdom: @hostile, location_region: @dest,
        composition: { "pikeman" => 200 })  # 200 * 40 = 8000 capacity

      Intercept.call(caravan: caravan, attacker_army: hostile_army, rng: Random.new(7))

      caravan.reload
      assert_equal "intercepted", caravan.status
      assert_not_nil caravan.intercepted_at

      hostile_state = Stockpile::Read.call(@hostile.reload)
      assert_equal 400, hostile_state["gold"]

      assert caravan.ledger_entries.all? { |e| e.status == "intercepted" }
      assert caravan.ledger_entries.all? { |e| e.attacker_handle == "Eve" }
    end

    test "escort wins → falls through to deliver" do
      caravan = dispatch_caravan(payload: { "gold" => 200 }, escort_units: { "knight" => 5 })
      # Make escort huge.
      caravan.escort_army.update!(composition: { "knight" => 100 })

      # Tiny hostile.
      hostile_army = create(:army, kingdom: @hostile, location_region: @dest,
        composition: { "scout" => 1 })

      Intercept.call(caravan: caravan, attacker_army: hostile_army, rng: Random.new(3))

      caravan.reload
      assert_equal "delivered", caravan.status
      assert_equal 200, Stockpile::Read.call(@receiver.reload)["gold"]
    end

    test "loot capped by hostile carrying capacity" do
      caravan = dispatch_caravan(payload: { "gold" => 400 }, escort_units: { "knight" => 5 })
      caravan.escort_army.update!(composition: { "scout" => 1 })

      # Hostile has tiny capacity: 5 levies = 5*50 = 250 capacity. Cargo is 400 → only 250 taken.
      hostile_army = create(:army, kingdom: @hostile, location_region: @dest,
        composition: { "levy" => 5 })

      Intercept.call(caravan: caravan, attacker_army: hostile_army, rng: Random.new(11))

      hostile_state = Stockpile::Read.call(@hostile.reload)
      assert_operator hostile_state["gold"], :<=, 250
      assert_operator hostile_state["gold"], :>, 0
    end

    test "emits dun.caravan.intercepted on loss" do
      caravan = dispatch_caravan(payload: { "gold" => 200 }, escort_units: { "knight" => 5 })
      caravan.escort_army.update!(composition: { "scout" => 1 })
      hostile_army = create(:army, kingdom: @hostile, location_region: @dest,
        composition: { "pikeman" => 200 })

      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.caravan.intercepted") do
        Intercept.call(caravan: caravan, attacker_army: hostile_army, rng: Random.new(2))
      end
      assert_equal 1, events.size
      assert_equal @hostile.id, events.first[:interceptor_kingdom_id]
    end
  end
end
