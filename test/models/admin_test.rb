require "test_helper"

class AdminTest < ActiveSupport::TestCase
  test "factory creates a valid admin" do
    assert build(:admin).valid?
  end

  test "email uniqueness is case-insensitive" do
    create(:admin, email: "BOB@example.com")

    dup = build(:admin, email: "bob@example.com")

    assert_not dup.valid?
  end

  test "an Admin and a Player with the same email are independent records" do
    Player.create!(email: "shared@example.com", name: "Shared P")
    admin = Admin.new(email: "shared@example.com", name: "Shared A")

    assert admin.valid?
    assert admin.save
  end
end
