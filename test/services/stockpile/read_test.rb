require "test_helper"

module Stockpile
  class ReadTest < ActiveSupport::TestCase
    test "materializes stored + elapsed * rate" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "quarry").update!(level: 4) # 100/h
      checkpoint = 2.hours.ago
      kingdom.update!(stockpiles: {
        "gold" => 0, "wood" => 0, "stone" => 100, "iron" => 0,
        "checkpoint_at" => checkpoint.iso8601
      })

      result = Read.call(kingdom)
      assert_equal 100 + (25 * 4 * 2), result["stone"]
    end

    test "clamps to current warehouse cap" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "warehouse").update!(level: 0)
      kingdom.buildings.find_by(kind: "quarry").update!(level: 10) # 250/h
      kingdom.update!(stockpiles: {
        "gold" => 0, "wood" => 0, "stone" => 4_000, "iron" => 0,
        "checkpoint_at" => 100.hours.ago.iso8601
      })

      result = Read.call(kingdom)
      assert_equal Buildings::Catalog.warehouse_cap(0), result["stone"]
    end

    test "negative elapsed (clock skew) does not shrink stockpile" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "quarry").update!(level: 4)
      kingdom.update!(stockpiles: {
        "gold" => 0, "wood" => 0, "stone" => 500, "iron" => 0,
        "checkpoint_at" => 1.hour.from_now.iso8601
      })
      result = Read.call(kingdom)
      assert_equal 500, result["stone"]
    end

    test "missing checkpoint_at treats now as checkpoint" do
      kingdom = create(:kingdom, :with_buildings)
      kingdom.buildings.find_by(kind: "quarry").update!(level: 4)
      kingdom.update!(stockpiles: { "gold" => 0, "wood" => 0, "stone" => 200, "iron" => 0 })
      result = Read.call(kingdom)
      assert_equal 200, result["stone"]
    end
  end
end
