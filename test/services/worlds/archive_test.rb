require "test_helper"

module Worlds
  class ArchiveTest < ActiveSupport::TestCase
    test "transitions an active world to archived with metadata" do
      world = create(:world, :active)
      Worlds::Archive.call(world, wonder_name: "The Whispering Tower")
      world.reload
      assert_equal "archived", world.status
      assert_not_nil world.archived_at
      assert_equal "The Whispering Tower", world.wonder_name
    end

    test "rejects an already-archived world" do
      world = create(:world, :archived)
      assert_raises(Worlds::Archive::WorldNotArchivable) do
        Worlds::Archive.call(world)
      end
    end

    test "rejects a proposed world (only active worlds can archive)" do
      world = create(:world, status: "proposed")
      assert_raises(Worlds::Archive::WorldNotArchivable) do
        Worlds::Archive.call(world)
      end
    end
  end
end
