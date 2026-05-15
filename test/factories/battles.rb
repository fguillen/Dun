FactoryBot.define do
  factory :battle do
    transient do
      server { create(:server) }
    end

    world  { create(:world, :active, server: server) }
    region { create(:region, world: world) }

    attacker_kingdom { create(:kingdom, world: world) }
    defender_kingdom { create(:kingdom, world: world) }

    march_order { nil }
    outcome     { "attacker_victory" }
    loot        { { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 } }
    log         { [] }
    started_at  { 10.minutes.ago }
    ended_at    { 1.minute.ago }

    trait :attacker_victory do
      outcome { "attacker_victory" }
    end

    trait :defender_victory do
      outcome { "defender_victory" }
    end

    trait :attacker_rout do
      outcome { "attacker_rout" }
    end

    trait :defender_rout do
      outcome { "defender_rout" }
    end
  end

  factory :battle_participant do
    association :battle
    kingdom { battle.attacker_kingdom }
    army    { nil }
    side    { "attacker" }
    starting_composition { { "levy" => 10 } }
    ending_composition   { { "levy" => 8 } }
    casualties           { { "levy" => 2 } }
  end
end
