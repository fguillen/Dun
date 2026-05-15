require "test_helper"

class ProductionCheckpointJobTest < ActiveJob::TestCase
  test "flushes stockpile checkpoint for kingdoms in grace + active worlds" do
    active_kingdom = create(:kingdom, :with_buildings)
    active_kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
    active_kingdom.world.update_columns(status: "active")
    active_kingdom.update!(stockpiles: {
      "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
      "checkpoint_at" => 1.hour.ago.iso8601
    })

    ProductionCheckpointJob.perform_now

    active_kingdom.reload
    assert active_kingdom.stockpiles["wood"].to_i.positive?
    checkpoint = Time.iso8601(active_kingdom.stockpiles["checkpoint_at"])
    assert_in_delta Time.current, checkpoint, 5
  end

  test "skips kingdoms in archived worlds" do
    server = create(:server)
    archived_world = create(:world, :archived, server: server)
    region = create(:region, world: archived_world)
    profile = create(:player_profile, server: server)
    kingdom = Kingdom.create!(world: archived_world, player_profile: profile, home_region: region, joined_at: Time.current,
      stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => 2.hours.ago.iso8601 })

    ProductionCheckpointJob.perform_now

    checkpoint = Time.iso8601(kingdom.reload.stockpiles["checkpoint_at"])
    assert_in_delta 2.hours.ago, checkpoint, 5
  end

  test "skips eliminated kingdoms" do
    kingdom = create(:kingdom, :with_buildings)
    kingdom.world.update_columns(status: "active")
    kingdom.update!(eliminated_at: 10.minutes.ago, stockpiles: {
      "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
      "checkpoint_at" => 1.hour.ago.iso8601
    })

    ProductionCheckpointJob.perform_now

    checkpoint = Time.iso8601(kingdom.reload.stockpiles["checkpoint_at"])
    assert_in_delta 1.hour.ago, checkpoint, 5
  end

  test "checkpoint drift across tick boundaries stays ≤ 1 minute" do
    kingdom = create(:kingdom, :with_buildings)
    kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
    kingdom.world.update_columns(status: "active")
    kingdom.update!(stockpiles: {
      "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0,
      "checkpoint_at" => Time.current.iso8601
    })

    travel 65.seconds do
      ProductionCheckpointJob.perform_now
      checkpoint = Time.iso8601(kingdom.reload.stockpiles["checkpoint_at"])
      assert_in_delta Time.current, checkpoint, 5
    end
  end
end
