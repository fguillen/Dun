require "test_helper"

module Wonders
  class DamageTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @home_region = create(:region, world: @world, name: "Defender Home")
      @attacker_region = create(:region, world: @world, name: "Attacker Home")
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @home_region)
      @attacker_kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @attacker_region)
      @wonder = create(:wonder, kingdom: @kingdom, status: "construction", hp: 10_000, milestones_paid: { "25" => true, "50" => true, "75" => true })
    end

    test "applies 50 HP × surviving Trebuchets" do
      Damage.call(wonder: @wonder, attacker_kingdom: @attacker_kingdom, trebuchets_surviving: 10)
      assert_equal 10_000 - 500, @wonder.reload.hp
    end

    test "creates a WonderDamageEvent audit row" do
      assert_difference -> { WonderDamageEvent.count }, 1 do
        Damage.call(wonder: @wonder, attacker_kingdom: @attacker_kingdom, trebuchets_surviving: 5)
      end
      ev = WonderDamageEvent.last
      assert_equal @wonder.id, ev.wonder_id
      assert_equal @attacker_kingdom.id, ev.attacker_kingdom_id
      assert_equal 10_000, ev.hp_before
      assert_equal 9_750, ev.hp_after
      assert_equal 5, ev.trebuchets_surviving
    end

    test "200 Trebuchets one-shot a full-HP Wonder and destroys it" do
      destroyed_events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { destroyed_events << p }, "dun.wonder.destroyed") do
        Damage.call(wonder: @wonder, attacker_kingdom: @attacker_kingdom, trebuchets_surviving: 200)
      end
      @wonder.reload
      assert_equal 0, @wonder.hp
      assert_equal "destroyed", @wonder.status
      assert_equal 1, destroyed_events.size
    end

    test "no-op when trebuchets_surviving is 0" do
      assert_no_difference -> { WonderDamageEvent.count } do
        Damage.call(wonder: @wonder, attacker_kingdom: @attacker_kingdom, trebuchets_surviving: 0)
      end
      assert_equal 10_000, @wonder.reload.hp
    end

    test "no-op when wonder already destroyed" do
      @wonder.update!(status: "destroyed", hp: 0)
      assert_no_difference -> { WonderDamageEvent.count } do
        Damage.call(wonder: @wonder, attacker_kingdom: @attacker_kingdom, trebuchets_surviving: 10)
      end
    end

    test "emits dun.wonder.damaged with hp_before/hp_after" do
      events = []
      ActiveSupport::Notifications.subscribed(->(_, _, _, _, p) { events << p }, "dun.wonder.damaged") do
        Damage.call(wonder: @wonder, attacker_kingdom: @attacker_kingdom, trebuchets_surviving: 3)
      end
      assert_equal 1, events.size
      assert_equal 10_000, events.first[:hp_before]
      assert_equal 9_850, events.first[:hp_after]
      assert_equal 150, events.first[:damage]
    end
  end
end
