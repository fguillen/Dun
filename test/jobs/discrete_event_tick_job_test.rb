require "test_helper"

class DiscreteEventTickJobTest < ActiveJob::TestCase
  test "processes a ripe build_completion event" do
    kingdom = create(:kingdom, :with_buildings)
    building = kingdom.buildings.find_by(kind: "quarry")
    order = create(:build_order, kingdom: kingdom, building: building, target_level: 2, completes_at: 1.minute.ago)
    event = create(:scheduled_event,
      world: kingdom.world,
      kind: "build_completion",
      fire_at: 1.minute.ago,
      payload: { "build_order_id" => order.id })

    DiscreteEventTickJob.perform_now

    assert event.reload.processed_at.present?
    assert_equal 2, building.reload.level
  end

  test "does not touch a future event" do
    world = create(:world, :grace)
    event = create(:scheduled_event, world: world, kind: "grace_expiry", fire_at: 1.hour.from_now)
    DiscreteEventTickJob.perform_now
    assert event.reload.pending?
  end
end
