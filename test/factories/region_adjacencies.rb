FactoryBot.define do
  factory :region_adjacency do
    transient do
      world { build(:world) }
    end

    region_a { create(:region, world: world) }
    region_b { create(:region, world: region_a.world) }

    after(:build) do |adj|
      if adj.region_a && adj.region_b && adj.region_a_id && adj.region_b_id && adj.region_a_id > adj.region_b_id
        adj.region_a, adj.region_b = adj.region_b, adj.region_a
      end
    end
  end
end
