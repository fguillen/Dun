FactoryBot.define do
  factory :ruin do
    association :region
    tier { "minor" }
    garrison { Ruin::GARRISONS["minor"] }
    cache    { Ruin::CACHES["minor"] }

    trait :standard do
      tier { "standard" }
      garrison { Ruin::GARRISONS["standard"] }
      cache    { Ruin::CACHES["standard"] }
    end

    trait :major do
      tier { "major" }
      garrison { Ruin::GARRISONS["major"] }
      cache    { Ruin::CACHES["major"] }
    end
  end
end
