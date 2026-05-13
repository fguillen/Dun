require "test_helper"

module Worlds
  class CancelTest < ActiveSupport::TestCase
    test "moves a proposed world to cancelled and stamps cancelled_at" do
      admin = create(:admin)
      world = create(:world, status: "proposed")

      Worlds::Cancel.call(world, by_admin: admin)

      world.reload
      assert_equal "cancelled", world.status
      assert_not_nil world.cancelled_at
    end

    test "raises WorldNotCancellable once a world is past proposed" do
      admin = create(:admin)

      [ :grace, :active, :archived, :cancelled ].each do |trait|
        world = create(:world, trait)
        assert_raises(Worlds::Cancel::WorldNotCancellable) do
          Worlds::Cancel.call(world, by_admin: admin)
        end
      end
    end
  end
end
