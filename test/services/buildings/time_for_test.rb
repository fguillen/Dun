require "test_helper"

module Buildings
  class TimeForTest < ActiveSupport::TestCase
    test "time formula: min(base * 1.55^(L-1), 24h)" do
      # Quarry base 120s
      assert_equal 120.seconds, TimeFor.call(kind: "quarry", level: 1)
      assert_in_delta (120 * (1.55**4)).round, TimeFor.call(kind: "quarry", level: 5).to_i, 1
    end

    test "24h cap kicks in for high levels" do
      result = TimeFor.call(kind: "siege_workshop", level: 20)
      assert_equal 24.hours.to_i, result.to_i
    end

    test "Stone Mason discount scales 2% per level, capped at -30%" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "stone_mason").update!(level: 5)
      base = TimeFor.call(kind: "quarry", level: 5).to_i
      discounted = TimeFor.call(kind: "quarry", level: 5, kingdom: kingdom).to_i
      assert_in_delta (base * 0.9).round, discounted, 1
    end

    test "Stone Mason discount caps at -30% beyond L15" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "stone_mason").update!(level: 20)
      base = TimeFor.call(kind: "quarry", level: 5).to_i
      discounted = TimeFor.call(kind: "quarry", level: 5, kingdom: kingdom).to_i
      assert_in_delta (base * 0.7).round, discounted, 1
    end

    test "no kingdom => no discount" do
      base = TimeFor.call(kind: "quarry", level: 5).to_i
      with_nil = TimeFor.call(kind: "quarry", level: 5, kingdom: nil).to_i
      assert_equal base, with_nil
    end
  end
end
