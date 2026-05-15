class StatsRefreshJob < ApplicationJob
  queue_as :default

  def perform
    # Phase 10/11 fill in: leaderboard recompute eligibility, audit clusters.
    # Wired into recurring config now so cadence is real from day one.
  end
end
