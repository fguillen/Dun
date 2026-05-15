require "test_helper"

module Armies
  class RenameTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom)
      @army = create(:army, kingdom: @kingdom, location_region: @kingdom.home_region, name: "Alpha")
    end

    test "renames the army" do
      Rename.call(army: @army, name: "Phoenix")
      assert_equal "Phoenix", @army.reload.name
    end

    test "rejects collision with another army in the same kingdom" do
      create(:army, kingdom: @kingdom, location_region: @kingdom.home_region, name: "Phoenix")
      assert_raises(Rename::NameTaken) do
        Rename.call(army: @army, name: "Phoenix")
      end
    end

    test "emits dun.army.renamed" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.army.renamed") do
        Rename.call(army: @army, name: "Phoenix")
      end

      assert_equal 1, events.size
      assert_equal "Phoenix", events.first[:name]
    end
  end
end
