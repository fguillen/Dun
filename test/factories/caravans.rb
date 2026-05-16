FactoryBot.define do
  factory :caravan do
    transient do
      server { create(:server) }
    end

    world  { create(:world, :active, server: server) }
    sender_kingdom   { create(:kingdom, world: world) }
    receiver_kingdom { create(:kingdom, world: world) }
    origin_region      { sender_kingdom.home_region   || create(:region, world: world) }
    destination_region { receiver_kingdom.home_region || create(:region, world: world) }
    escort_army        { create(:army, kingdom: sender_kingdom, status: "marching", composition: { "levy" => 5 }) }
    outbound_march_order do
      create(:march_order,
        army: escort_army,
        origin_region: origin_region,
        target_region: destination_region,
        intent: "caravan",
        path: [ origin_region.id, destination_region.id ])
    end
    payload         { { "gold" => 100 } }
    escort_units    { { "levy" => 5 } }
    status          { "in_transit" }
    dispatched_at   { Time.current }
    arrives_at      { 1.hour.from_now }
  end
end
