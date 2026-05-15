FactoryBot.define do
  factory :army do
    association :kingdom
    location_region { kingdom.home_region || create(:region, world: kingdom.world) }
    sequence(:name) { |n| "Army #{n}" }
    status { "home" }
    composition { { "levy" => 10 } }

    trait :garrison do
      name { Army::GARRISON_NAME }
    end

    trait :marching do
      status { "marching" }
    end

    trait :engaged do
      status { "engaged" }
    end

    trait :returning do
      status { "returning" }
    end
  end
end
