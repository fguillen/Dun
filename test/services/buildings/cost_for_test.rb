require "test_helper"

module Buildings
  class CostForTest < ActiveSupport::TestCase
    test "cost formula: round(base * 1.75^(L-1))" do
      base = Catalog::BASE_COSTS["quarry"]
      [ 1, 5, 10, 15, 20 ].each do |level|
        result = CostFor.call(kind: "quarry", level: level)
        Kingdom::RESOURCES.each do |resource|
          expected = (base[resource] * (1.75**(level - 1))).round
          assert_equal expected, result[resource], "quarry #{resource} at L#{level}"
        end
      end
    end

    test "Town Hall L1 returns base costs verbatim" do
      assert_equal({ "gold" => 200, "wood" => 200, "stone" => 200, "iron" => 100 },
                   CostFor.call(kind: "town_hall", level: 1))
    end

    test "unknown kind raises" do
      assert_raises(ArgumentError) { CostFor.call(kind: "castle", level: 1) }
    end

    test "level < 1 raises" do
      assert_raises(ArgumentError) { CostFor.call(kind: "quarry", level: 0) }
    end
  end
end
