FactoryBot.define do
  factory :server do
    sequence(:slug) { |n| "server-#{n}" }
    sequence(:name) { |n| "Server #{n}" }
    association :owner, factory: :admin

    after(:create) do |server, _|
      server.server_adminships.find_or_create_by!(admin: server.owner) do |adminship|
        adminship.role = "owner"
      end
    end
  end
end
