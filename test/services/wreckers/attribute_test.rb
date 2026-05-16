require "test_helper"

module Wreckers
  class AttributeTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @builder_profile = create(:player_profile, server: @world.server)
      @builder = create(:kingdom, world: @world, player_profile: @builder_profile, home_region: @region)
      @attacker_profile = create(:player_profile, server: @world.server)
      @attacker = create(:kingdom, world: @world, player_profile: @attacker_profile, home_region: @region)
      @second_attacker_profile = create(:player_profile, server: @world.server)
      @second_attacker = create(:kingdom, world: @world, player_profile: @second_attacker_profile, home_region: @region)
      @wonder = create(:wonder, kingdom: @builder, hp: 0, status: "destroyed", destroyed_at: Time.current)
    end

    test "credits the attacker whose damage event brought HP to 0" do
      WonderDamageEvent.create!(
        wonder: @wonder, attacker_kingdom: @attacker, trebuchets_surviving: 5,
        hp_before: 200, hp_after: 0, occurred_at: Time.current
      )
      Attribute.call(wonder: @wonder)
      assert_equal 1, @attacker_profile.stats.reload.wonders_destroyed
    end

    test "tie broken by larger Trebuchet contribution" do
      now = Time.current
      WonderDamageEvent.create!(wonder: @wonder, attacker_kingdom: @attacker,        trebuchets_surviving: 3, hp_before: 100, hp_after: 0, occurred_at: now)
      WonderDamageEvent.create!(wonder: @wonder, attacker_kingdom: @second_attacker, trebuchets_surviving: 9, hp_before: 100, hp_after: 0, occurred_at: now)
      Attribute.call(wonder: @wonder)
      assert_equal 0, @attacker_profile.stats.reload.wonders_destroyed
      assert_equal 1, @second_attacker_profile.stats.reload.wonders_destroyed
    end

    test "tie broken by earliest dispatch when Trebuchet counts are equal" do
      WonderDamageEvent.create!(wonder: @wonder, attacker_kingdom: @attacker,        trebuchets_surviving: 4, hp_before: 100, hp_after: 0, occurred_at: 2.hours.ago)
      WonderDamageEvent.create!(wonder: @wonder, attacker_kingdom: @second_attacker, trebuchets_surviving: 4, hp_before: 100, hp_after: 0, occurred_at: 1.hour.ago)
      Attribute.call(wonder: @wonder)
      assert_equal 1, @attacker_profile.stats.reload.wonders_destroyed
      assert_equal 0, @second_attacker_profile.stats.reload.wonders_destroyed
    end

    test "no-ops when there is no killing-blow event" do
      WonderDamageEvent.create!(wonder: @wonder, attacker_kingdom: @attacker, trebuchets_surviving: 1, hp_before: 200, hp_after: 50, occurred_at: Time.current)
      result = Attribute.call(wonder: @wonder)
      assert_nil result
      assert_equal 0, @attacker_profile.stats.reload.wonders_destroyed
    end
  end
end
