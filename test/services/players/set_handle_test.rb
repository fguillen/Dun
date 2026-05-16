require "test_helper"

module Players
  class SetHandleTest < ActiveSupport::TestCase
    setup do
      @profile = create(:player_profile)
    end

    test "updates the handle when not locked" do
      Players::SetHandle.call(@profile, "NewName")
      assert_equal "NewName", @profile.reload.handle
    end

    test "raises HandleLockedError when locked? is true" do
      @profile.stubs(:locked?).returns(true)
      assert_raises(Players::HandleLockedError) do
        Players::SetHandle.call(@profile, "TooLate")
      end
    end

    test "validation errors propagate" do
      assert_raises(ActiveRecord::RecordInvalid) do
        Players::SetHandle.call(@profile, "admin")
      end
    end

    test "rejects a handle retired by a deleted account within 30 days" do
      RetiredHandle.create!(server: @profile.server, handle_lower: "stark", freed_at: 5.days.ago)
      assert_raises(Players::SetHandle::HandleReservedError) do
        Players::SetHandle.call(@profile, "Stark")
      end
    end

    test "allows a previously retired handle once the 30-day window passes" do
      RetiredHandle.create!(server: @profile.server, handle_lower: "stark", freed_at: 31.days.ago)
      Players::SetHandle.call(@profile, "Stark")
      assert_equal "Stark", @profile.reload.handle
    end
  end
end
