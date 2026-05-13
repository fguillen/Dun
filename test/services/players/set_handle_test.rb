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
  end
end
