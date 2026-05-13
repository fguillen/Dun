FactoryBot.define do
  factory :region do
    association :world
    sequence(:name) { |n| "Region #{n}" }
    terrain { "plains" }
    position { { "x" => rand, "y" => rand } }
    spawn_eligible { false }
    is_hub { false }
  end
end
