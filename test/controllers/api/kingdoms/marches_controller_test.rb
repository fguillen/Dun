require "test_helper"

module Api
  module Kingdoms
    class MarchesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @player = create(:player, email: "alice@example.com")
        ServerMembership.create!(server: @server, player: @player)
        ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
        @profile = create(:player_profile, server: @server, player: @player)

        @world = create(:world, :grace, server: @server)
        @home = create(:region, world: @world, terrain: "plains", name: "Home")
        @target = create(:region, world: @world, terrain: "mountain", name: "Target")
        @isolated = create(:region, world: @world, terrain: "plains", name: "Isolated")
        RegionAdjacency.connect(@home, @target)

        @kingdom = create(:kingdom, world: @world, player_profile: @profile, home_region: @home)
        @army = create(:army, kingdom: @kingdom, location_region: @home, name: "Vanguard",
          composition: { "levy" => 10 })
        authenticate_as_player(@player)
      end

      def regions_index
        preview = response.parsed_body["army_previews"].find { |p| p["army_id"] == @army.id }
        preview["regions"].index_by { |r| r["region_id"] }
      end

      test "GET preview returns one entry per army with per-region reachability" do
        get "/v1/kingdoms/#{@kingdom.id}/march/preview", headers: auth_headers
        assert_response :success

        previews = response.parsed_body["army_previews"]
        assert_equal 1, previews.size
        assert_equal @army.id, previews.first["army_id"]
        assert_equal "Vanguard", previews.first["army_name"]
        assert_equal @world.regions.count, previews.first["regions"].size

        regions = regions_index
        assert_equal 0, regions[@home.id]["hops"]
        assert regions[@target.id]["reachable"]
        assert regions[@target.id]["duration_seconds"] > 0
        assert_not_nil regions[@target.id]["arrives_at"]
        assert_equal false, regions[@isolated.id]["reachable"]
      end

      test "GET preview matches the actual dispatch ETA" do
        get "/v1/kingdoms/#{@kingdom.id}/march/preview", headers: auth_headers
        previewed = regions_index[@target.id]["duration_seconds"]

        order = ::Marches::Dispatch.call(army: @army, target_region: @target, intent: "reinforce")
        actual = order.arrives_at - order.dispatched_at

        assert_in_delta actual, previewed, 1.0
      end

      test "GET preview returns an empty list for a kingdom with no armies" do
        other_world = create(:world, :grace, server: @server)
        empty_kingdom = create(:kingdom, world: other_world, player_profile: @profile,
          home_region: create(:region, world: other_world))
        get "/v1/kingdoms/#{empty_kingdom.id}/march/preview", headers: auth_headers
        assert_response :success
        assert_equal [], response.parsed_body["army_previews"]
      end

      test "GET preview returns 404 for non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/march/preview", headers: auth_headers
        assert_response :not_found
      end

      test "GET preview rejects an unauthenticated request" do
        get "/v1/kingdoms/#{@kingdom.id}/march/preview"
        assert_response :unauthorized
      end
    end
  end
end
