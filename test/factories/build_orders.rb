FactoryBot.define do
  factory :build_order do
    association :kingdom
    building { create(:building, kingdom: kingdom) }
    target_level { 2 }
    started_at { Time.current }
    completes_at { 1.hour.from_now }
  end
end
