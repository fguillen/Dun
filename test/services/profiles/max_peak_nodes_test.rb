require "test_helper"

module Profiles
  class MaxPeakNodesTest < ActiveSupport::TestCase
    setup do
      @profile = create(:player_profile)
    end

    test "folds candidate into lifetime peak via GREATEST" do
      MaxPeakNodes.call(player_profile: @profile, candidate: 7)
      assert_equal 7, @profile.stats.reload.peak_nodes

      MaxPeakNodes.call(player_profile: @profile, candidate: 3)
      assert_equal 7, @profile.stats.reload.peak_nodes

      MaxPeakNodes.call(player_profile: @profile, candidate: 12)
      assert_equal 12, @profile.stats.reload.peak_nodes
    end

    test "no-ops on non-positive candidate" do
      MaxPeakNodes.call(player_profile: @profile, candidate: 0)
      assert_equal 0, @profile.stats.reload.peak_nodes
    end
  end
end
