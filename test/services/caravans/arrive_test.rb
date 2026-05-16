require "test_helper"

module Caravans
  class ArriveTest < ActiveSupport::TestCase
    setup do
      @server = create(:server)
      @world  = create(:world, :active, server: @server)

      @origin = create(:region, world: @world, terrain: "plains", name: "OriginHome")
      @dest   = create(:region, world: @world, terrain: "plains", name: "DestHome")
      RegionAdjacency.connect(@origin, @dest)

      @sender_profile   = create(:player_profile, server: @server, handle: "Alice")
      @receiver_profile = create(:player_profile, server: @server, handle: "Bob")
      @hostile_profile  = create(:player_profile, server: @server, handle: "Eve")

      @sender = create(:kingdom, :with_buildings,
        world: @world, player_profile: @sender_profile, home_region: @origin,
        stockpiles: { "gold" => 1_000, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })
      @receiver = create(:kingdom, :with_buildings,
        world: @world, player_profile: @receiver_profile, home_region: @dest,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })
      @hostile_home = create(:region, world: @world, terrain: "plains", name: "HostileHome")
      @hostile = create(:kingdom, world: @world, player_profile: @hostile_profile,
        home_region: @hostile_home,
        stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
                      "checkpoint_at" => Time.current.iso8601 })

      @source_army = create(:army, kingdom: @sender, location_region: @origin,
        composition: { "knight" => 10 })
    end

    def dispatch_caravan
      Caravans::Dispatch.call(
        sender_kingdom: @sender, receiver_kingdom: @receiver,
        source_army: @source_army,
        payload: { "gold" => 200 }, escort_units: { "knight" => 5 })
    end

    test "delivers when destination has no hostile army" do
      caravan = dispatch_caravan
      Arrive.call(caravan: caravan)
      assert_equal "delivered", caravan.reload.status
    end

    test "ignores sender's own army at destination" do
      caravan = dispatch_caravan
      # Sender has an old army parked at the destination — not hostile.
      create(:army, kingdom: @sender, location_region: @dest, composition: { "scout" => 5 })

      Arrive.call(caravan: caravan)
      assert_equal "delivered", caravan.reload.status
    end

    test "ignores receiver's own army at destination" do
      caravan = dispatch_caravan
      create(:army, kingdom: @receiver, location_region: @dest, composition: { "pikeman" => 30 })

      Arrive.call(caravan: caravan)
      assert_equal "delivered", caravan.reload.status
    end

    test "intercepts when a third-party hostile is camped at destination" do
      caravan = dispatch_caravan
      # Shrink escort so hostile clearly wins.
      caravan.escort_army.update!(composition: { "scout" => 1 })
      create(:army, kingdom: @hostile, location_region: @dest,
        composition: { "pikeman" => 100 })

      Arrive.call(caravan: caravan)
      assert_equal "intercepted", caravan.reload.status
    end

    test "ignores marching/returning hostiles at destination" do
      caravan = dispatch_caravan
      create(:army, kingdom: @hostile, location_region: @dest,
        status: "marching", composition: { "pikeman" => 100 })

      Arrive.call(caravan: caravan)
      assert_equal "delivered", caravan.reload.status
    end

    test "picks strongest hostile when multiple are present" do
      caravan = dispatch_caravan
      caravan.escort_army.update!(composition: { "scout" => 1 })

      # Two hostile kingdoms at destination — pick the stronger one.
      hostile2_profile = create(:player_profile, server: @server, handle: "Frank")
      hostile2_home = create(:region, world: @world, name: "Hostile2Home")
      hostile2 = create(:kingdom, world: @world, player_profile: hostile2_profile,
        home_region: hostile2_home)
      weak = create(:army, kingdom: hostile2, location_region: @dest,
        composition: { "levy" => 1 })
      strong = create(:army, kingdom: @hostile, location_region: @dest,
        composition: { "pikeman" => 100 })

      Arrive.call(caravan: caravan)

      caravan.reload
      assert_equal "intercepted", caravan.status
      assert caravan.ledger_entries.all? { |e| e.attacker_handle == "Eve" }
    end
  end
end
