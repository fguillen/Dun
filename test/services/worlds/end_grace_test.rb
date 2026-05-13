require "test_helper"

module Worlds
  class EndGraceTest < ActiveSupport::TestCase
    test "flips a grace world to active and releases unused spawn slots" do
      world = create(:world, :grace, seed: "0000000000002f35", min_players: 12)
      MapGeneration::Generate.call(world: world, players_count: 12)

      # Claim 3 spawn regions
      spawn_regions = world.regions.where(spawn_eligible: true).limit(3)
      spawn_regions.each_with_index do |region, i|
        profile = create(:player_profile, server: world.server)
        Kingdom.create!(world: world, player_profile: profile, home_region: region, joined_at: Time.current - i.minutes)
      end

      total_spawns_before = world.regions.where(spawn_eligible: true).count
      assert total_spawns_before > 3

      Worlds::EndGrace.call(world)
      world.reload

      assert_equal "active", world.status
      assert_equal 3, world.regions.where(spawn_eligible: true).count
    end

    test "is a no-op when the world is not in grace" do
      world = create(:world, :active)
      Worlds::EndGrace.call(world)
      assert_equal "active", world.reload.status
    end
  end
end
