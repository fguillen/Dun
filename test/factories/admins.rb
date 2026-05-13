FactoryBot.define do
  factory :admin do
    sequence(:email) { |n| "admin#{n}@example.com" }
    name { "Admin #{SecureRandom.hex(2)}" }
  end
end
