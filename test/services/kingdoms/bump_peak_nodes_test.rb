require "test_helper"

module Kingdoms
  class BumpPeakNodesTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @profile = create(:player_profile, server: @world.server)
      @kingdom = create(:kingdom, world: @world, player_profile: @profile, home_region: @region, peak_nodes: 0)
    end

    test "bumps peak_nodes via GREATEST as nodes are owned" do
      2.times do
        node = create(:node, region: @region)
        node.update!(owner_kingdom_id: @kingdom.id)
      end
      BumpPeakNodes.call(kingdom_id: @kingdom.id)
      assert_equal 2, @kingdom.reload.peak_nodes
    end

    test "never decreases peak_nodes" do
      @kingdom.update!(peak_nodes: 5)
      BumpPeakNodes.call(kingdom_id: @kingdom.id)
      assert_equal 5, @kingdom.reload.peak_nodes
    end
  end
end
