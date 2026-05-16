require "test_helper"

module Profiles
  class IncrementTest < ActiveSupport::TestCase
    setup do
      @profile = create(:player_profile)
    end

    test "atomically increments allowlisted columns" do
      Increment.call(player_profile: @profile, deltas: { rounds_played: 1, raids_launched: 3 })
      @profile.stats.reload
      assert_equal 1, @profile.stats.rounds_played
      assert_equal 3, @profile.stats.raids_launched
    end

    test "raises on unknown columns" do
      assert_raises(Increment::UnknownColumn) do
        Increment.call(player_profile: @profile, deltas: { bogus: 1 })
      end
    end

    test "skips zero-valued deltas" do
      Increment.call(player_profile: @profile, deltas: { rounds_played: 0 })
      assert_equal 0, @profile.stats.reload.rounds_played
    end

    test "creates a stats row if missing" do
      @profile.stats.destroy!
      Increment.call(player_profile: @profile, deltas: { rounds_played: 2 })
      assert_equal 2, @profile.reload.stats.rounds_played
    end
  end
end
