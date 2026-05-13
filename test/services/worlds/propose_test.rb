require "test_helper"

module Worlds
  class ProposeTest < ActiveSupport::TestCase
    test "creates a proposed world with a random hex seed" do
      admin = create(:admin)
      server = create(:server, owner: admin)

      world = Worlds::Propose.call(
        server: server,
        organizer_admin: admin,
        name: "Spring 2026",
        min_players: 4,
        t0_at: 1.day.from_now
      )

      assert world.persisted?
      assert_equal "proposed", world.status
      assert_equal "spring-2026", world.slug
      assert_equal server.id, world.server_id
      assert_match(/\A[0-9a-f]{16}\z/, world.seed)
    end

    test "accepts a custom slug" do
      admin = create(:admin)
      server = create(:server, owner: admin)

      world = Worlds::Propose.call(
        server: server, organizer_admin: admin, name: "Whatever",
        min_players: 4, t0_at: 1.day.from_now, slug: "my-custom-slug"
      )

      assert_equal "my-custom-slug", world.slug
    end

    test "two worlds on the same server cannot share a slug" do
      admin = create(:admin)
      server = create(:server, owner: admin, max_concurrent_worlds: 10)

      Worlds::Propose.call(
        server: server, organizer_admin: admin, name: "Spring",
        min_players: 4, t0_at: 1.day.from_now
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        Worlds::Propose.call(
          server: server, organizer_admin: admin, name: "Spring",
          min_players: 4, t0_at: 2.days.from_now
        )
      end
    end

    test "enforces server.max_concurrent_worlds across proposed/grace/active" do
      admin = create(:admin)
      server = create(:server, owner: admin, max_concurrent_worlds: 2)
      create(:world, server: server, status: "proposed")
      create(:world, :grace, server: server)

      assert_raises(Worlds::Propose::ConcurrentWorldLimitReached) do
        Worlds::Propose.call(
          server: server, organizer_admin: admin, name: "Third",
          min_players: 4, t0_at: 1.day.from_now
        )
      end
    end

    test "archived and cancelled worlds do not count toward the concurrent limit" do
      admin = create(:admin)
      server = create(:server, owner: admin, max_concurrent_worlds: 1)
      create(:world, :archived, server: server)
      create(:world, :cancelled, server: server)

      assert_nothing_raised do
        Worlds::Propose.call(
          server: server, organizer_admin: admin, name: "Fresh",
          min_players: 4, t0_at: 1.day.from_now
        )
      end
    end

    test "max_concurrent_worlds of 0 freezes world creation entirely (per \u00a716.7)" do
      admin = create(:admin)
      server = create(:server, owner: admin, max_concurrent_worlds: 0)

      assert_raises(Worlds::Propose::ConcurrentWorldLimitReached) do
        Worlds::Propose.call(
          server: server, organizer_admin: admin, name: "First",
          min_players: 4, t0_at: 1.day.from_now
        )
      end

      assert_equal 0, server.worlds.count
    end
  end
end
