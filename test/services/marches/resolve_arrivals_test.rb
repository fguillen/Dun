require "test_helper"

module Marches
  class ResolveArrivalsTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :grace)
      @home = create(:region, world: @world, terrain: "plains", name: "Home")
      @target = create(:region, world: @world, terrain: "plains", name: "Target")
      RegionAdjacency.connect(@home, @target)

      @kingdom = create(:kingdom, world: @world, home_region: @home)
      @army_a = create(:army, kingdom: @kingdom, location_region: @home, name: "Alpha",
        composition: { "knight" => 5 })
      @army_b = create(:army, kingdom: @kingdom, location_region: @home, name: "Bravo",
        composition: { "knight" => 5 })
    end

    test "resolves multiple ripe march orders in arrives_at order" do
      a = Dispatch.call(army: @army_a, target_region: @target, intent: "reinforce")
      b = Dispatch.call(army: @army_b, target_region: @target, intent: "reinforce")
      a.update!(arrives_at: 2.minutes.ago)
      b.update!(arrives_at: 1.minute.ago)

      ResolveArrivals.call(@kingdom)
      a.reload
      b.reload
      assert a.arrived_at < b.arrived_at
    end

    test "leaves future arrivals alone" do
      a = Dispatch.call(army: @army_a, target_region: @target, intent: "reinforce")
      a.update!(arrives_at: 1.hour.from_now)

      ResolveArrivals.call(@kingdom)
      assert a.reload.active?
    end
  end
end
