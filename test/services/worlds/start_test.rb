require "test_helper"

module Worlds
  class StartTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @admin = create(:admin)
      @server = create(:server, owner: @admin)
      @world = create(:world,
                      server: @server,
                      seed: "0000000000002f35",
                      min_players: 12,
                      t0_at: 1.minute.ago,
                      status: "proposed")
      12.times do |i|
        player = create(:player, email: "player#{i}@example.com")
        profile = create(:player_profile, server: @server, player: player, handle: "Player#{i}")
        Kingdom.create!(world: @world, player_profile: profile, home_region: nil, joined_at: i.minutes.ago)
      end
    end

    test "transitions to grace, generates a map, and assigns home regions" do
      Worlds::Start.call(@world)
      @world.reload

      assert_equal "grace", @world.status
      assert_not_nil @world.grace_closes_at
      assert_in_delta (@world.t0_at + 72.hours).to_f, @world.grace_closes_at.to_f, 1

      assert_equal 36, @world.regions.count
      @world.kingdoms.each do |k|
        assert_not_nil k.home_region_id
        assert k.home_region.spawn_eligible
      end
    end

    test "is idempotent (a second call after success leaves the world in grace)" do
      Worlds::Start.call(@world)
      first_region_count = @world.reload.regions.count
      Worlds::Start.call(@world)
      assert_equal first_region_count, @world.reload.regions.count
      assert_equal "grace", @world.status
    end

    test "raises WorldNotStartable when fewer than min_players have joined" do
      @world.kingdoms.first.destroy!
      assert_raises(Worlds::Start::WorldNotStartable) do
        Worlds::Start.call(@world)
      end
      assert_equal "proposed", @world.reload.status
    end

    test "is a no-op when t0_at is still in the future" do
      @world.update!(t0_at: 1.day.from_now)
      Worlds::Start.call(@world)
      assert_equal "proposed", @world.reload.status
    end

    test "schedules an EndGraceJob for the grace deadline" do
      assert_enqueued_with(job: Worlds::EndGraceJob, args: [ @world.id ]) do
        Worlds::Start.call(@world)
      end
    end
  end
end
