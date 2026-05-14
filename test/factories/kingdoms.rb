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

    trait :with_buildings do
      after(:create) do |kingdom|
        Buildings::Catalog::KINDS.each do |kind|
          level = Buildings::Catalog::STARTER_LEVELS.fetch(kind, 0)
          kingdom.buildings.find_or_create_by!(kind: kind) { |b| b.level = level }
        end
      end
    end
  end
end
