FactoryBot.define do
  factory :server_access do
    association :server
    kind { "invite" }
    sequence(:value) { |n| "guest#{n}@example.com" }

    factory :domain_access do
      kind  { "domain" }
      value { "*@example.com" }
    end
  end
end
