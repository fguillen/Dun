require "test_helper"

class StatsRefreshJobTest < ActiveJob::TestCase
  test "runs without error (Phase 10/11 stub)" do
    assert_nothing_raised { StatsRefreshJob.perform_now }
  end
end
