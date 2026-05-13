require "test_helper"

class PlayerTest < ActiveSupport::TestCase
  test "factory creates a valid player" do
    assert build(:player).valid?
  end

  test "email is normalized and uniqueness is case-insensitive" do
    create(:player, email: "ALICE@example.com")

    dup = build(:player, email: "alice@example.com")

    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "name is required" do
    player = build(:player, name: "")

    assert_not player.valid?
    assert_includes player.errors[:name], "can't be blank"
  end
end
