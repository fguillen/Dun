require "test_helper"

class PlayerProfileStatsTest < ActiveSupport::TestCase
  test "auto-creates a stats row on profile create" do
    profile = create(:player_profile)
    assert_not_nil profile.stats
    PlayerProfileStats::COUNTER_COLUMNS.each do |c|
      assert_equal 0, profile.stats.public_send(c).to_i
    end
  end

  test "to_counters returns int values for every column" do
    profile = create(:player_profile)
    counters = profile.stats.to_counters
    assert_equal PlayerProfileStats::COUNTER_COLUMNS.sort, counters.keys.sort
    counters.each_value { |v| assert_kind_of Integer, v }
  end

  test "enforces uniqueness on player_profile" do
    profile = create(:player_profile)
    assert_raises(ActiveRecord::RecordNotUnique) do
      PlayerProfileStats.create!(player_profile_id: profile.id)
    end
  end
end
