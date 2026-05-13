FactoryBot.define do
  factory :kingdom do
    transient do
      server { create(:server) }
    end

    world           { create(:world, :grace, server: server) }
    player_profile  { create(:player_profile, server: world.server) }
    home_region     { create(:region, world: world) }
    stockpiles      { { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 } }
    metadata        { {} }

    trait :proposed do
      world  { create(:world, server: server) }
      home_region { nil }
    end
  end
end
