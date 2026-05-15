require "test_helper"

module Units
  class TrainingTimeForTest < ActiveSupport::TestCase
    test "L1 returns the base time exactly" do
      Catalog::KINDS.each do |unit|
        base = Catalog.base_train_time_for(unit)
        assert_equal base.seconds, TrainingTimeFor.call(unit: unit, building_level: 1)
      end
    end

    test "formula is base * 0.95^(L-1)" do
      base = Catalog.base_train_time_for("knight")
      [1, 5, 10, 15, 20].each do |level|
        expected = (base * (0.95**(level - 1))).round
        assert_equal expected.seconds, TrainingTimeFor.call(unit: "knight", building_level: level)
      end
    end

    test "L20 ≈ 0.377 of base" do
      Catalog::KINDS.each do |unit|
        base = Catalog.base_train_time_for(unit)
        result = TrainingTimeFor.call(unit: unit, building_level: 20).to_i
        assert_in_delta (base * 0.377), result, [ (base * 0.005), 1 ].max
      end
    end

    test "strictly decreasing across levels for every unit" do
      Catalog::KINDS.each do |unit|
        prior = Float::INFINITY
        (1..20).each do |level|
          current = TrainingTimeFor.call(unit: unit, building_level: level).to_i
          assert current <= prior, "expected non-increasing time for #{unit} L#{level}"
          prior = current
        end
      end
    end

    test "level 0 clamps to L1 (defensive)" do
      base = Catalog.base_train_time_for("levy")
      assert_equal base.seconds, TrainingTimeFor.call(unit: "levy", building_level: 0)
    end
  end
end
