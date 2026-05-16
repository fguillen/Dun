require "test_helper"

# Phase 8 — full caravan lifecycle via the tick engine.
# Dispatches a caravan, advances the ScheduledEvent queue, and asserts the
# Stockpile, Caravan, and TradeLedger state transitions for both the delivery
# happy path and the third-party interception path.
class CaravanLifecycleTest < ActionDispatch::IntegrationTest
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
      name: "Vanguard", composition: { "knight" => 10 })
  end

  test "dispatch -> tick -> delivery -> return march merges escort" do
    caravan = ::Caravans::Dispatch.call(
      sender_kingdom: @sender, receiver_kingdom: @receiver,
      source_army: @source_army,
      payload: { "gold" => 300 }, escort_units: { "knight" => 5 })

    # Force the arrival event to be ripe by backdating arrives_at + fire_at.
    outbound = caravan.outbound_march_order
    outbound.update!(arrives_at: 1.minute.ago)
    ScheduledEvent.where(kind: "march_arrival").update_all(fire_at: 1.minute.ago)

    ::ScheduledEvents::Drain.call
    caravan.reload
    assert_equal "delivered", caravan.status
    assert_equal 300, Stockpile::Read.call(@receiver.reload)["gold"]

    # Ledger now reflects delivered.
    entries = ::TradeLedgerEntry.where(caravan_id: caravan.id)
    assert entries.all? { |e| e.status == "delivered" }
    assert_equal [ "Alice" ], entries.map(&:sender_handle_at_send).uniq
    assert_equal [ "Bob" ],   entries.map(&:receiver_handle_at_send).uniq

    # Return march pre-scheduled. Force-ripe and drain again.
    return_order = caravan.return_march_order
    assert return_order
    return_order.update!(arrives_at: 1.minute.ago)
    ScheduledEvent.where(kind: "march_arrival", processed_at: nil).update_all(fire_at: 1.minute.ago)

    ::ScheduledEvents::Drain.call

    # Sender's home army composition has grown back by the escort's survivors.
    home_army = @sender.armies.where(location_region_id: @origin.id, status: "home")
      .where.not(name: Army::GARRISON_NAME).order(:created_at).first
    assert_equal 10, home_army.composition["knight"].to_i
  end

  test "dispatch -> tick -> interception when third-party camped at destination" do
    hostile_profile = create(:player_profile, server: @server, handle: "Eve")
    hostile_home = create(:region, world: @world, terrain: "plains", name: "HostileHome")
    hostile = create(:kingdom, world: @world, player_profile: hostile_profile, home_region: hostile_home,
      stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
                    "checkpoint_at" => Time.current.iso8601 })
    create(:army, kingdom: hostile, location_region: @dest,
      name: "Ambush", composition: { "pikeman" => 100 })

    caravan = ::Caravans::Dispatch.call(
      sender_kingdom: @sender, receiver_kingdom: @receiver,
      source_army: @source_army,
      payload: { "gold" => 300 }, escort_units: { "knight" => 5 })
    # Shrink escort drastically so the hostile wins.
    caravan.escort_army.update!(composition: { "scout" => 1 })

    caravan.outbound_march_order.update!(arrives_at: 1.minute.ago)
    ScheduledEvent.where(kind: "march_arrival").update_all(fire_at: 1.minute.ago)

    ::ScheduledEvents::Drain.call
    caravan.reload
    assert_equal "intercepted", caravan.status
    assert_operator Stockpile::Read.call(hostile.reload)["gold"], :>, 0
    assert_equal 0, Stockpile::Read.call(@receiver.reload)["gold"]

    entries = ::TradeLedgerEntry.where(caravan_id: caravan.id)
    assert entries.all? { |e| e.status == "intercepted" }
    assert entries.all? { |e| e.attacker_handle == "Eve" }
  end
end
