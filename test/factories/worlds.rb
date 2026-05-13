FactoryBot.define do
  factory :world do
    association :server
    sequence(:name) { |n| "World #{n}" }
    sequence(:slug) { |n| "world-#{n}" }
    seed { SecureRandom.hex(8) }
    status { "proposed" }
    min_players { 4 }
    auto_cancel_after_hours { 168 }
    t0_at { 1.day.from_now }

    trait :grace do
      status { "grace" }
      t0_at { 1.hour.ago }
      grace_closes_at { 71.hours.from_now }
    end

    trait :active do
      status { "active" }
      t0_at { 80.hours.ago }
      grace_closes_at { 8.hours.ago }
    end

    trait :archived do
      status { "archived" }
      t0_at { 30.days.ago }
      grace_closes_at { 27.days.ago }
      archived_at { 1.day.ago }
    end

    trait :cancelled do
      status { "cancelled" }
      cancelled_at { 1.hour.ago }
    end
  end
end
