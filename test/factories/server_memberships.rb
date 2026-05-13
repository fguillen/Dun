FactoryBot.define do
  factory :server_membership do
    association :server
    association :player
  end
end
