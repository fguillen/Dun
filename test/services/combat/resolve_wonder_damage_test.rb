require "test_helper"

module Combat
  class ResolveWonderDamageTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @attacker_home = create(:region, world: @world, terrain: "plains", name: "AttackerHome")
      @defender_home = create(:region, world: @world, terrain: "plains", name: "DefenderHome")
      RegionAdjacency.connect(@attacker_home, @defender_home)

      @attacker = create(:kingdom, :with_buildings, world: @world, home_region: @attacker_home)
      @defender = create(:kingdom, :with_buildings, world: @world, home_region: @defender_home)
    end

    def dispatch_attack(army, target)
      order = Marches::Dispatch.call(army: army, target_region: target, intent: "attack")
      order.update!(arrives_at: 1.minute.ago)
      order
    end

    test "surviving Trebuchets damage the Wonder on attacker victory at home region" do
      wonder = create(:wonder, kingdom: @defender, status: "construction", hp: 10_000,
        milestones_paid: { "25" => true, "50" => true, "75" => true })

      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 200, "trebuchet" => 20 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "levy" => 1 })

      order = dispatch_attack(attacker_army, @defender_home)
      battle = Resolve.call(march_order: order, rng: Random.new(7))

      assert_includes %w[attacker_victory defender_rout], battle.outcome
      wonder.reload
      assert_operator wonder.hp, :<, 10_000
      assert WonderDamageEvent.where(wonder: wonder).exists?
    end

    test "no Wonder damage when attacker loses" do
      wonder = create(:wonder, kingdom: @defender, status: "construction", hp: 10_000,
        milestones_paid: { "25" => true, "50" => true, "75" => true })

      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "levy" => 5, "trebuchet" => 5 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "pikeman" => 200, "royal_guard" => 50 })

      order = dispatch_attack(attacker_army, @defender_home)
      battle = Resolve.call(march_order: order, rng: Random.new(11))
      assert_includes %w[defender_victory attacker_rout], battle.outcome
      assert_equal 10_000, wonder.reload.hp
      refute WonderDamageEvent.where(wonder: wonder).exists?
    end

    test "no Wonder damage when battle happens away from defender home region" do
      far_region = create(:region, world: @world, name: "Far")
      RegionAdjacency.connect(@defender_home, far_region)
      RegionAdjacency.connect(@attacker_home, far_region)

      wonder = create(:wonder, kingdom: @defender, status: "construction", hp: 10_000,
        milestones_paid: { "25" => true, "50" => true, "75" => true })

      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 100, "trebuchet" => 50 })
      create(:army, kingdom: @defender, location_region: far_region, name: "Forward",
        composition: { "levy" => 1 })

      order = dispatch_attack(attacker_army, far_region)
      Resolve.call(march_order: order, rng: Random.new(5))
      assert_equal 10_000, wonder.reload.hp
    end

    test "no Wonder damage when defender has no live Wonder" do
      attacker_army = create(:army, kingdom: @attacker, location_region: @attacker_home,
        composition: { "knight" => 200, "trebuchet" => 20 })
      create(:army, kingdom: @defender, location_region: @defender_home, name: "Garrison",
        composition: { "levy" => 1 })

      order = dispatch_attack(attacker_army, @defender_home)
      Resolve.call(march_order: order, rng: Random.new(7))
      assert_equal 0, WonderDamageEvent.count
    end
  end
end
