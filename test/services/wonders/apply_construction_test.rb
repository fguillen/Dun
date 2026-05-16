require "test_helper"

module Wonders
  class ApplyConstructionTest < ActiveSupport::TestCase
    setup do
      @world = create(:world, :active)
      @region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings, world: @world, home_region: @region)
      @t0 = Time.current
      @wonder = create(:wonder,
        kingdom: @kingdom,
        status: "construction",
        hp: 1_000,
        started_at: @t0,
        construction_started_at: @t0,
        last_construction_at: @t0
      )
    end

    test "accrues 100 HP per hour from last_construction_at" do
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 5.hours)
      @wonder.reload
      assert_equal 1_500, @wonder.hp
      assert_equal (@t0 + 5.hours).to_i, @wonder.last_construction_at.to_i
    end

    test "is a no-op when status is not construction" do
      @wonder.update!(status: "foundation")
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 5.hours)
      assert_equal 1_000, @wonder.reload.hp
    end

    test "pauses at 25% milestone (2_500 HP) with pending_milestone_percent" do
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 20.hours)  # would yield 3000 HP
      @wonder.reload
      assert_equal 2_500, @wonder.hp
      assert_equal 25, @wonder.pending_milestone_percent
    end

    test "no-op while pending_milestone_percent is set" do
      @wonder.update!(pending_milestone_percent: 25, hp: 2_500)
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 30.hours)
      assert_equal 2_500, @wonder.reload.hp
      assert_equal 25, @wonder.reload.pending_milestone_percent
    end

    test "respects paused_until" do
      @wonder.update!(paused_until: @t0 + 2.hours)
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 1.hour)
      assert_equal 1_000, @wonder.reload.hp
    end

    test "resumes construction from paused_until once the pause expires" do
      @wonder.update!(paused_until: @t0 + 2.hours)
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 4.hours)
      # 2 hours of unpaused time → 200 HP
      assert_equal 1_200, @wonder.reload.hp
    end

    test "caps HP at target_hp (10_000)" do
      @wonder.update!(hp: 9_950, milestones_paid: { "25" => true, "50" => true, "75" => true })
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 5.hours)
      assert_equal 10_000, @wonder.reload.hp
    end

    test "idempotent: multiple calls at the same instant produce the same result" do
      now = @t0 + 5.hours
      ApplyConstruction.call(wonder: @wonder, now: now)
      hp1 = @wonder.reload.hp
      ApplyConstruction.call(wonder: @wonder, now: now)
      assert_equal hp1, @wonder.reload.hp
    end

    test "milestones at 50% and 75% trigger when their thresholds are crossed" do
      @wonder.update!(hp: 2_500, milestones_paid: { "25" => true, "50" => false, "75" => false }, last_construction_at: @t0)
      ApplyConstruction.call(wonder: @wonder, now: @t0 + 30.hours)
      assert_equal 5_000, @wonder.reload.hp
      assert_equal 50, @wonder.reload.pending_milestone_percent
    end
  end
end
