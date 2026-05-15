FactoryBot.define do
  factory :training_order do
    association :kingdom
    building { kingdom.buildings.find_by(kind: "barracks") || create(:building, kingdom: kingdom, kind: "barracks", level: 1) }
    building_kind { "barracks" }
    unit { "levy" }
    count { 5 }
    started_at { Time.current }
    completes_at { 10.minutes.from_now }
  end
end
