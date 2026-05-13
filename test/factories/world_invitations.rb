FactoryBot.define do
  factory :world_invitation do
    association :world
    sequence(:email) { |n| "invitee#{n}@example.com" }
    association :invited_by_admin, factory: :admin
  end
end
