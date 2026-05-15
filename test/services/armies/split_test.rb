require "test_helper"

module Armies
  class SplitTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom)
      @garrison = create(:army, :garrison,
        kingdom: @kingdom, location_region: @kingdom.home_region,
        composition: { "levy" => 10, "knight" => 5 })
    end

    test "carves a new army with the requested units" do
      result = Split.call(army: @garrison, units: { "levy" => 4, "knight" => 2 }, name: "Strike Force")
      new_army = result[:new]
      source = result[:source]

      assert_equal "Strike Force", new_army.name
      assert_equal "home", new_army.status
      assert_equal @garrison.location_region_id, new_army.location_region_id
      assert_equal({ "levy" => 4, "knight" => 2 }, new_army.composition)

      source.reload
      assert_equal({ "levy" => 6, "knight" => 3 }, source.composition)
    end

    test "rejects when source army is not home" do
      @garrison.update!(status: "marching")
      assert_raises(Split::NotHome) do
        Split.call(army: @garrison, units: { "levy" => 1 }, name: "Foo")
      end
    end

    test "rejects when units exceed source composition" do
      assert_raises(Split::InsufficientUnits) do
        Split.call(army: @garrison, units: { "levy" => 99 }, name: "Foo")
      end
    end

    test "rejects when split would be empty" do
      assert_raises(Split::EmptySplit) do
        Split.call(army: @garrison, units: {}, name: "Foo")
      end
    end

    test "destroys an emptied non-garrison source" do
      strike = create(:army, kingdom: @kingdom, location_region: @kingdom.home_region,
        name: "Vanguard", composition: { "levy" => 3 })
      result = Split.call(army: strike, units: { "levy" => 3 }, name: "Heir")
      assert_nil result[:source]
      assert_nil Army.find_by(id: strike.id)
    end

    test "preserves an emptied garrison" do
      result = Split.call(army: @garrison, units: { "levy" => 10, "knight" => 5 }, name: "All-In")
      assert_not_nil result[:source]
      assert @garrison.reload.empty?
    end

    test "name uniqueness within kingdom enforced" do
      Split.call(army: @garrison, units: { "levy" => 1 }, name: "Strike Force")
      assert_raises(ActiveRecord::RecordInvalid) do
        Split.call(army: @garrison, units: { "levy" => 1 }, name: "Strike Force")
      end
    end

    test "emits dun.army.split" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.army.split") do
        Split.call(army: @garrison, units: { "levy" => 1 }, name: "Probe")
      end

      assert_equal 1, events.size
      assert_equal @garrison.id, events.first[:source_army_id]
    end
  end
end
