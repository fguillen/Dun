FactoryBot.define do
  factory :player do
    sequence(:email) { |n| "player#{n}@example.com" }
    name { "Player #{SecureRandom.hex(2)}" }
  end
end
