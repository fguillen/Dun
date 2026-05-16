require "test_helper"

module Wonders
  class CatalogTest < ActiveSupport::TestCase
    test "NAMES contains the six committed Wonder choices" do
      assert_equal %w[sky_tower eternal_citadel cathedral_of_ages library_of_worlds crown_of_kings black_spire], Catalog::NAMES
    end

    test "foundation_cost matches §16.2 (25% per resource)" do
      assert_equal(
        { "gold" => 200_000, "wood" => 150_000, "stone" => 600_000, "iron" => 200_000 },
        Catalog.foundation_cost
      )
    end

    test "milestone_cost matches §16.2 (10% per resource)" do
      assert_equal(
        { "gold" => 80_000, "wood" => 60_000, "stone" => 240_000, "iron" => 80_000 },
        Catalog.milestone_cost
      )
    end

    test "consecration_cost matches §16.2 (5% per resource)" do
      assert_equal(
        { "gold" => 40_000, "wood" => 30_000, "stone" => 120_000, "iron" => 40_000 },
        Catalog.consecration_cost
      )
    end

    test "name? validates against the menu" do
      assert Catalog.name?("sky_tower")
      refute Catalog.name?("definitely_not_a_wonder")
    end

    test "prerequisites include town_hall, quarry, siege_workshop and 3 nodes" do
      assert_equal 10, Catalog::PREREQUISITES["town_hall"]
      assert_equal 10, Catalog::PREREQUISITES["quarry"]
      assert_equal 5, Catalog::PREREQUISITES["siege_workshop"]
      assert_equal 3, Catalog::NODES_REQUIRED
    end
  end
end
