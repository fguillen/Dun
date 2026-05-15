FactoryBot.define do
  factory :march_order do
    association :army
    origin_region { army.location_region }
    target_region { create(:region, world: army.kingdom.world) }
    intent { "reinforce" }
    path { [ origin_region.id, target_region.id ] }
    dispatched_at { Time.current }
    arrives_at { 1.hour.from_now }
  end
end
