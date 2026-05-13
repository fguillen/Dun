require "test_helper"

module Kingdoms
  class BootstrapTest < ActiveSupport::TestCase
    # §16.8 table verbatim
    BONUS_TABLE = [
      [ 0,   0    ],
      [ 12,  1_000 ],
      [ 24,  2_000 ],
      [ 48,  4_000 ],
      [ 72,  4_000 ],
      [ 96,  4_000 ]
    ].freeze

    test "stockpile bonus matches \u00a716.8 across the table" do
      BONUS_TABLE.each do |hours, expected_bonus|
        kingdom = create(:kingdom)
        Kingdoms::Bootstrap.call(kingdom, hours_since_t0: hours)
        kingdom.reload

        Kingdom::RESOURCES.each do |r|
          assert_equal Kingdom::STARTER_STOCKPILE + expected_bonus, kingdom.stockpile(r),
                       "expected #{r} = #{Kingdom::STARTER_STOCKPILE + expected_bonus} at #{hours}h, got #{kingdom.stockpile(r)}"
        end
        assert_equal expected_bonus, kingdom.metadata["late_joiner_bonus"]
      end
    end

    test "records the starter buildings and Levy metadata (\u00a713)" do
      kingdom = create(:kingdom)
      Kingdoms::Bootstrap.call(kingdom, hours_since_t0: 0)
      kingdom.reload

      assert_equal 1, kingdom.metadata.dig("starter_buildings", "barracks")
      assert_equal 1, kingdom.metadata.dig("starter_buildings", "walls")
      assert_equal 1, kingdom.metadata.dig("starter_buildings", "watchtower")
      assert_equal 20, kingdom.metadata["starter_levy"]
    end

    test "stockpile_at writes a checkpoint timestamp" do
      kingdom = create(:kingdom)
      Kingdoms::Bootstrap.call(kingdom, hours_since_t0: 0)
      assert_not_nil kingdom.reload.stockpiles["checkpoint_at"]
    end
  end
end
