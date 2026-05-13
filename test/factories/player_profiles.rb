FactoryBot.define do
  factory :player_profile do
    association :server
    association :player
    sequence(:handle) { |n| "Player#{n}" }
    sequence(:real_name) { |n| "Real Name #{n}" }
  end
end
