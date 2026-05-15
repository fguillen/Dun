FactoryBot.define do
  factory :scheduled_event do
    association :world, factory: [ :world, :active ]
    kind { "build_completion" }
    payload { {} }
    fire_at { 1.minute.from_now }
  end
end
