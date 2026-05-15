require "test_helper"

class BuildingTest < ActiveSupport::TestCase
  test "walls? identifies the walls building kind" do
    assert build(:building, kind: "walls", level: 3).walls?
    refute build(:building, kind: "barracks", level: 3).walls?
  end

  test "current_wall_hp falls back to level × WALL_HP_PER_LEVEL when nil" do
    walls = build(:building, kind: "walls", level: 4, wall_hp: nil)
    assert_equal 4 * Building::WALL_HP_PER_LEVEL, walls.current_wall_hp
  end

  test "current_wall_hp returns the stored wall_hp when set" do
    walls = build(:building, kind: "walls", level: 4, wall_hp: 2_500)
    assert_equal 2_500, walls.current_wall_hp
  end

  test "current_wall_hp is zero for non-walls buildings" do
    assert_equal 0, build(:building, kind: "barracks", level: 5).current_wall_hp
  end
end
