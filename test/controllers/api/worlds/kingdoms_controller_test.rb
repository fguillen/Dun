require "test_helper"

module Api
  module Worlds
    class KingdomsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @world = create(:world, :active, server: @server)
        @region = create(:region, world: @world)

        @player = create(:player, email: "alice@example.com")
        ServerMembership.create!(server: @server, player: @player)
        ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
        @profile = create(:player_profile, server: @server, player: @player, handle: "Alice")
        @kingdom = create(:kingdom, world: @world, player_profile: @profile, home_region: @region)

        authenticate_as_player(@player)
      end

      test "lists every kingdom with handle, home region, counts, and join time" do
        region_b = create(:region, world: @world)
        bob_profile = create(:player_profile, server: @server, handle: "Bob")
        bob_kingdom = create(:kingdom, world: @world, player_profile: bob_profile, home_region: region_b)
        create(:node, region: region_b, owner_kingdom_id: bob_kingdom.id)
        create(:ruin, region: region_b, claimed_by_kingdom_id: bob_kingdom.id)

        get "/v1/worlds/#{@world.id}/kingdoms", headers: auth_headers
        assert_response :success
        kingdoms = response.parsed_body["kingdoms"]
        assert_equal 2, kingdoms.size

        by_id = kingdoms.index_by { |k| k["kingdom_id"] }

        mine = by_id[@kingdom.id]
        assert_equal "Alice", mine["handle"]
        assert mine["is_you"]
        assert_equal @region.id, mine["home_region_id"]
        assert_equal @region.name, mine["home_region_name"]
        assert_equal 0, mine["nodes_controlled"]
        assert_equal 0, mine["ruins_claimed"]
        assert_nil mine["title"]
        assert_nil mine["wonder"]
        assert_equal false, mine["eliminated"]
        assert mine["joined_at"]

        bob = by_id[bob_kingdom.id]
        assert_equal "Bob", bob["handle"]
        assert_not bob["is_you"]
        assert_equal 1, bob["nodes_controlled"]
        assert_equal 1, bob["ruins_claimed"]
      end

      test "includes a coarse wonder summary when the kingdom has a Wonder" do
        create(:wonder, kingdom: @kingdom, status: "construction", hp: 5_000)

        get "/v1/worlds/#{@world.id}/kingdoms", headers: auth_headers
        assert_response :success
        entry = response.parsed_body["kingdoms"].find { |k| k["kingdom_id"] == @kingdom.id }
        assert_equal "sky_tower", entry["wonder"]["name"]
        assert_equal "construction", entry["wonder"]["status"]
        assert_equal 50, entry["wonder"]["hp_pct"]
      end

      test "surfaces the player's cross-round reputation title" do
        past_world = create(:world, server: @server, name: "Eldoria")
        PlayerTitle.create!(player_profile: @profile, world: past_world,
                            kind: PlayerTitle::CHAMPION, awarded_at: 1.day.ago)

        get "/v1/worlds/#{@world.id}/kingdoms", headers: auth_headers
        assert_response :success
        entry = response.parsed_body["kingdoms"].find { |k| k["kingdom_id"] == @kingdom.id }
        assert_equal "[Champion of Eldoria]", entry["title"]
      end

      test "reports eliminated kingdoms" do
        @kingdom.update!(eliminated_at: Time.current)

        get "/v1/worlds/#{@world.id}/kingdoms", headers: auth_headers
        assert_response :success
        entry = response.parsed_body["kingdoms"].find { |k| k["kingdom_id"] == @kingdom.id }
        assert entry["eliminated"]
      end

      test "returns null home region for a stub kingdom before the world starts" do
        proposed = create(:world, server: @server, status: "proposed", t0_at: 1.day.from_now)
        stub = create(:kingdom, :proposed, world: proposed, player_profile: @profile)

        get "/v1/worlds/#{proposed.id}/kingdoms", headers: auth_headers
        assert_response :success
        entry = response.parsed_body["kingdoms"].find { |k| k["kingdom_id"] == stub.id }
        assert_nil entry["home_region_id"]
        assert_nil entry["home_region_name"]
      end

      test "returns 404 to non-members of the world's server" do
        stranger = create(:player)
        authenticate_as_player(stranger)

        get "/v1/worlds/#{@world.id}/kingdoms", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
