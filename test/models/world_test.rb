require "test_helper"

class WorldTest < ActiveSupport::TestCase
  test "factory builds a valid world" do
    world = build(:world)
    assert world.valid?, world.errors.full_messages.join(", ")
  end

  test "slug is unique per server, case-insensitive" do
    server = create(:server)
    create(:world, server: server, slug: "spring-2026")
    dupe = build(:world, server: server, slug: "Spring-2026")
    assert_not dupe.valid?
    assert_includes dupe.errors[:slug], "has already been taken"
  end

  test "slug uniqueness is scoped to server (same slug allowed on different servers)" do
    other_server = create(:server)
    create(:world, slug: "spring-2026")
    twin = build(:world, server: other_server, slug: "spring-2026")
    assert twin.valid?, twin.errors.full_messages.join(", ")
  end

  test "slug must match the 3-40 char lowercase format" do
    world = build(:world, slug: "AB")
    assert_not world.valid?
    assert_includes world.errors[:slug].first, "must be 3-40 chars"
  end

  test "status must be one of the allowed values" do
    world = build(:world, status: "lol")
    assert_not world.valid?
    assert_includes world.errors[:status], "is not included in the list"
  end

  test "min_players must be positive integer" do
    world = build(:world, min_players: 0)
    assert_not world.valid?
  end

  test "predicate helpers for each status" do
    %w[proposed grace active archived cancelled].each do |s|
      world = build(:world, status: s, t0_at: 1.day.from_now)
      assert world.public_send("#{s}?"), "expected #{s}? to be true on a #{s} world"
    end
  end

  test "joinable? true for proposed and grace, false otherwise" do
    assert build(:world, status: "proposed").joinable?
    assert build(:world, :grace).joinable?
    assert_not build(:world, :active).joinable?
    assert_not build(:world, :archived).joinable?
    assert_not build(:world, :cancelled).joinable?
  end

  test "seed_int parses the hex seed deterministically" do
    world = build(:world, seed: "deadbeef00000000")
    assert_equal 0xdeadbeef00000000, world.seed_int
  end
end
