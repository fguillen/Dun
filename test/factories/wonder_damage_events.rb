FactoryBot.define do
  factory :wonder_damage_event do
    association :wonder
    association :attacker_kingdom, factory: :kingdom
    trebuchets_surviving { 10 }
    hp_before { 1_000 }
    hp_after { 500 }
    occurred_at { Time.current }
  end
end
