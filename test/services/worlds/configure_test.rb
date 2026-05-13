require "test_helper"

module Worlds
  class ConfigureTest < ActiveSupport::TestCase
    test "updates whitelisted attrs on a proposed world" do
      world = create(:world, name: "Old", min_players: 4)
      new_t0 = 2.days.from_now

      Worlds::Configure.call(world, name: "New", min_players: 8, t0_at: new_t0, auto_cancel_after_hours: 96)

      world.reload
      assert_equal "New", world.name
      assert_equal 8, world.min_players
      assert_in_delta new_t0.to_f, world.t0_at.to_f, 1
      assert_equal 96, world.auto_cancel_after_hours
    end

    test "ignores attrs outside the whitelist (e.g. status)" do
      world = create(:world, status: "proposed")
      Worlds::Configure.call(world, status: "active", slug: "rogue", server_id: 999_999)

      world.reload
      assert_equal "proposed", world.status
      assert_not_equal "rogue", world.slug
    end

    test "raises WorldNotConfigurable once the world is past proposed" do
      [ :grace, :active, :archived, :cancelled ].each do |trait|
        world = create(:world, trait)
        assert_raises(Worlds::Configure::WorldNotConfigurable) do
          Worlds::Configure.call(world, name: "Renamed")
        end
      end
    end
  end
end
