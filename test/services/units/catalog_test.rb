require "test_helper"

module Units
  class CatalogTest < ActiveSupport::TestCase
    test "KINDS lists exactly the 8 units from §16.3" do
      assert_equal %w[levy archer pikeman knight catapult royal_guard scout trebuchet], Catalog::KINDS
    end

    test "TERRAIN_IMMUNE = knight, scout (§16.10)" do
      assert_equal %w[knight scout], Catalog::TERRAIN_IMMUNE
    end

    test "TRAINS_AT maps each military building to the units it produces (§9)" do
      assert_equal %w[levy archer pikeman], Catalog::TRAINS_AT["barracks"]
      assert_equal %w[knight scout royal_guard], Catalog::TRAINS_AT["stable"]
      assert_equal %w[catapult trebuchet], Catalog::TRAINS_AT["siege_workshop"]
    end

    test "every unit appears in exactly one TRAINS_AT mapping" do
      mapped = Catalog::TRAINS_AT.values.flatten
      assert_equal Catalog::KINDS.sort, mapped.sort
    end

    test "kind? recognizes all KINDS and rejects others" do
      Catalog::KINDS.each { |u| assert Catalog.kind?(u) }
      assert_not Catalog.kind?("ninja")
      assert_not Catalog.kind?("")
      assert_not Catalog.kind?(nil)
    end

    test "stats_for returns the §16.3 stat block for each unit" do
      Catalog::KINDS.each do |unit|
        stats = Catalog.stats_for(unit)
        assert_kind_of Integer, stats[:atk]
        assert_kind_of Integer, stats[:def]
        assert_kind_of Integer, stats[:hp]
        assert stats[:speed].is_a?(Numeric)
        assert_kind_of Integer, stats[:capacity]
        assert_kind_of Integer, stats[:base_train_time]
        assert_equal %w[gold wood stone iron], stats[:cost].keys
      end
    end

    test "Knight stats match §16.3" do
      stats = Catalog.stats_for("knight")
      assert_equal 25, stats[:atk]
      assert_equal 12, stats[:def]
      assert_equal 20, stats[:hp]
      assert_equal 1.0, stats[:speed]
      assert_equal 80, stats[:capacity]
      assert_equal({ "gold" => 100, "wood" => 20, "stone" => 0, "iron" => 80 }, stats[:cost])
      assert_equal 240, stats[:base_train_time]
    end

    test "Trebuchet stats match §16.3" do
      stats = Catalog.stats_for("trebuchet")
      assert_equal 20, stats[:atk]
      assert_equal 6, stats[:def]
      assert_equal 50, stats[:hp]
      assert_equal 0.2, stats[:speed]
      assert_equal 250, stats[:capacity]
      assert_equal({ "gold" => 1500, "wood" => 2000, "stone" => 8000, "iron" => 4000 }, stats[:cost])
      assert_equal 2700, stats[:base_train_time]
    end

    test "accessor helpers return the same data as stats_for" do
      assert_equal 4, Catalog.atk_for("levy")
      assert_equal 6, Catalog.def_for("levy")
      assert_equal 10, Catalog.hp_for("levy")
      assert_equal 0.5, Catalog.speed_for("levy")
      assert_equal 50, Catalog.capacity_for("levy")
      assert_equal({ "gold" => 20, "wood" => 30, "stone" => 0, "iron" => 10 }, Catalog.cost_for("levy"))
      assert_equal 45, Catalog.base_train_time_for("levy")
    end
  end
end
