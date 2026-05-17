require "test_helper"

module Worlds
  class ForceStartTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @admin = create(:admin)
      @server = create(:server, owner: @admin)
    end

    test "transitions a proposed world to grace even when t0_at is in the future and min_players is unmet" do
      world = create(:world,
                     server: @server,
                     seed: "0000000000002f35",
                     min_players: 24,
                     t0_at: 7.days.from_now,
                     status: "proposed")
      12.times do |i|
        player = create(:player, email: "player#{i}@example.com")
        profile = create(:player_profile, server: @server, player: player, handle: "Player#{i}")
        Kingdom.create!(world: world, player_profile: profile, home_region: nil, joined_at: i.minutes.ago)
      end

      freeze_time do
        Worlds::ForceStart.call(world)
        world.reload

        assert_equal "grace", world.status
        assert_in_delta Time.current.to_f, world.t0_at.to_f, 1
        assert_in_delta (Time.current + 72.hours).to_f, world.grace_closes_at.to_f, 1
      end

      world.kingdoms.each do |k|
        assert_not_nil k.home_region_id
        assert k.home_region.spawn_eligible
      end
    end

    test "force-starts an empty proposed world (zero kingdoms)" do
      world = create(:world,
                     server: @server,
                     min_players: 4,
                     t0_at: 1.day.from_now,
                     status: "proposed")

      MapGeneration::Generate.expects(:call).with(world: instance_of(World), players_count: 0).once

      freeze_time do
        Worlds::ForceStart.call(world)
        world.reload

        assert_equal "grace", world.status
        assert_equal 0, world.kingdoms.count
        assert_in_delta Time.current.to_f, world.t0_at.to_f, 1
        assert_in_delta (Time.current + 72.hours).to_f, world.grace_closes_at.to_f, 1
      end
    end

    test "enqueues an EndGraceJob for the new grace deadline" do
      world = create(:world,
                     server: @server,
                     min_players: 4,
                     t0_at: 1.day.from_now,
                     status: "proposed")
      MapGeneration::Generate.stubs(:call)

      assert_enqueued_with(job: Worlds::EndGraceJob, args: [ world.id ]) do
        Worlds::ForceStart.call(world)
      end
    end

    test "leaves the original StartJob harmless: a subsequent Worlds::Start no-ops" do
      world = create(:world,
                     server: @server,
                     seed: "0000000000002f35",
                     min_players: 24,
                     t0_at: 7.days.from_now,
                     status: "proposed")
      12.times do |i|
        player = create(:player, email: "player#{i}@example.com")
        profile = create(:player_profile, server: @server, player: player, handle: "Player#{i}")
        Kingdom.create!(world: world, player_profile: profile, home_region: nil, joined_at: i.minutes.ago)
      end

      Worlds::ForceStart.call(world)
      assert_equal "grace", world.reload.status

      Worlds::Start.call(world)
      assert_equal "grace", world.reload.status
    end

    %w[grace active cancelled archived].each do |status|
      test "raises WorldNotForceStartable when world is #{status}" do
        world = create(:world, status.to_sym, server: @server)

        assert_raises(Worlds::ForceStart::WorldNotForceStartable) do
          Worlds::ForceStart.call(world)
        end
        assert_equal status, world.reload.status
      end
    end

    test "a second force-start raises (world is no longer proposed)" do
      world = create(:world,
                     server: @server,
                     min_players: 4,
                     t0_at: 1.day.from_now,
                     status: "proposed")
      MapGeneration::Generate.stubs(:call)

      Worlds::ForceStart.call(world)
      assert_raises(Worlds::ForceStart::WorldNotForceStartable) do
        Worlds::ForceStart.call(world)
      end
    end
  end
end
