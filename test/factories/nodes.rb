FactoryBot.define do
  factory :node do
    association :region
    resource { "gold" }
    tier { "standard" }
    base_rate { Node::TIER_BASE_RATE["standard"] }
    garrison { Node::WILDERNESS_GARRISONS["standard"] }
    is_home_hoard { false }

    trait :rich do
      tier { "rich" }
      base_rate { Node::TIER_BASE_RATE["rich"] }
      garrison { Node::WILDERNESS_GARRISONS["rich"] }
    end

    trait :poor do
      tier { "poor" }
      base_rate { Node::TIER_BASE_RATE["poor"] }
      garrison { Node::WILDERNESS_GARRISONS["poor"] }
    end
  end
end
