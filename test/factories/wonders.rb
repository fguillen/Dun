FactoryBot.define do
  factory :wonder do
    association :kingdom
    name { "sky_tower" }
    status { "construction" }
    hp { 1_000 }
    target_hp { 10_000 }
    started_at { Time.current }
    construction_started_at { Time.current }
    last_construction_at { Time.current }
    milestones_paid { { "25" => false, "50" => false, "75" => false } }
    repaired_hp_by_phase { { "foundation" => 0, "construction" => 0, "consecration" => 0 } }

    trait :foundation do
      status { "foundation" }
      hp { 1_000 }
    end

    trait :consecration do
      status { "consecration" }
      hp { 10_000 }
      consecration_at { Time.current }
      milestones_paid { { "25" => true, "50" => true, "75" => true } }
    end

    trait :completed do
      status { "completed" }
      hp { 10_000 }
      consecration_at { 25.hours.ago }
      completed_at { 1.hour.ago }
      milestones_paid { { "25" => true, "50" => true, "75" => true } }
    end

    trait :destroyed do
      status { "destroyed" }
      hp { 0 }
      destroyed_at { Time.current }
    end
  end
end
