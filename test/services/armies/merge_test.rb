require "test_helper"

module Armies
  class MergeTest < ActiveSupport::TestCase
    setup do
      @kingdom = create(:kingdom)
      region = @kingdom.home_region
      @into = create(:army, kingdom: @kingdom, location_region: region,
        name: "Alpha", composition: { "levy" => 5, "archer" => 3 })
      @from = create(:army, kingdom: @kingdom, location_region: region,
        name: "Bravo", composition: { "levy" => 2, "knight" => 1 })
    end

    test "sums compositions into target army" do
      Merge.call(into: @into, from: @from)
      @into.reload
      assert_equal({ "levy" => 7, "archer" => 3, "knight" => 1 }, @into.composition)
    end

    test "destroys the source army" do
      Merge.call(into: @into, from: @from)
      assert_nil Army.find_by(id: @from.id)
    end

    test "rejects merging into self" do
      assert_raises(ArgumentError) do
        Merge.call(into: @into, from: @into)
      end
    end

    test "rejects different kingdoms" do
      other_kingdom = create(:kingdom, world: @kingdom.world)
      foreign = create(:army, kingdom: other_kingdom, location_region: other_kingdom.home_region)
      assert_raises(Merge::IncompatibleKingdom) do
        Merge.call(into: @into, from: foreign)
      end
    end

    test "rejects different regions" do
      elsewhere = create(:region, world: @kingdom.world)
      @from.update!(location_region: elsewhere)
      assert_raises(Merge::IncompatibleLocation) do
        Merge.call(into: @into, from: @from)
      end
    end

    test "rejects when either army is not home" do
      @from.update!(status: "marching")
      assert_raises(Merge::IncompatibleStatus) do
        Merge.call(into: @into, from: @from)
      end
    end

    test "emits dun.army.merged" do
      events = []
      callback = ->(_, _, _, _, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "dun.army.merged") do
        Merge.call(into: @into, from: @from)
      end

      assert_equal 1, events.size
      assert_equal @into.id, events.first[:into_army_id]
      assert_equal @from.id, events.first[:from_army_id]
    end
  end
end
