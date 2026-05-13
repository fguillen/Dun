FactoryBot.define do
  factory :server_adminship do
    association :server
    association :admin
    role { "admin" }
  end
end
