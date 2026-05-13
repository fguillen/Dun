require "test_helper"

module Worlds
  class JoinTest < ActiveSupport::TestCase
    setup do
      @admin = create(:admin)
      @server = create(:server, owner: @admin)
      @player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: @server, player: @player)
      ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
    end

    test "joining a proposed world creates a stub kingdom with no home region" do
      world = create(:world, server: @server, status: "proposed", min_players: 4, t0_at: 1.day.from_now)
      kingdom = Worlds::Join.call(world: world, player: @player)
      assert kingdom.persisted?
      assert_nil kingdom.home_region_id
      assert_equal @player.id, kingdom.player_profile.player_id
    end

    test "joining is idempotent (re-join returns the same kingdom)" do
      world = create(:world, server: @server, status: "proposed", min_players: 4, t0_at: 1.day.from_now)
      first = Worlds::Join.call(world: world, player: @player)
      second = Worlds::Join.call(world: world, player: @player)
      assert_equal first.id, second.id
    end

    test "joining a grace world assigns a spawn region and bootstraps" do
      world = create(:world, :grace, server: @server, seed: "0000000000002f35", min_players: 12)
      MapGeneration::Generate.call(world: world, players_count: 12)

      kingdom = Worlds::Join.call(world: world, player: @player)
      assert_not_nil kingdom.home_region_id
      assert kingdom.stockpile("gold") >= 500
    end

    test "joining an active or archived world is rejected" do
      [ :active, :archived, :cancelled ].each do |trait|
        world = create(:world, trait, server: @server)
        assert_raises(Worlds::Join::WorldNotJoinable) do
          Worlds::Join.call(world: world, player: @player)
        end
      end
    end

    test "joining is rejected for a player not admitted to the server" do
      stranger = create(:player, email: "stranger@nope.example")
      world = create(:world, server: @server, status: "proposed", min_players: 4, t0_at: 1.day.from_now)
      assert_raises(Worlds::Join::ServerAccessDenied) do
        Worlds::Join.call(world: world, player: stranger)
      end
    end

    test "joining is rejected for a player without a server membership" do
      admitted_but_not_joined = create(:player, email: "bob@example.com")
      ServerAccess.create!(server: @server, kind: "invite", value: admitted_but_not_joined.email)
      world = create(:world, server: @server, status: "proposed", min_players: 4, t0_at: 1.day.from_now)
      assert_raises(Worlds::Join::NotServerMember) do
        Worlds::Join.call(world: world, player: admitted_but_not_joined)
      end
    end

    test "max_worlds_per_account caps concurrent worlds for one account" do
      @server.update!(max_worlds_per_account: 1)
      world_a = create(:world, server: @server, status: "proposed", min_players: 4, t0_at: 1.day.from_now)
      world_b = create(:world, server: @server, status: "proposed", min_players: 4, t0_at: 1.day.from_now, slug: "second-world")

      Worlds::Join.call(world: world_a, player: @player)
      assert_raises(Worlds::Join::WorldAccountLimitReached) do
        Worlds::Join.call(world: world_b, player: @player)
      end
    end
  end
end
