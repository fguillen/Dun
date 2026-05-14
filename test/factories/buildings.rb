FactoryBot.define do
  factory :building do
    association :kingdom
    kind { "quarry" }
    level { 1 }
  end
end
