require "test_helper"

module Api
  module Worlds
    class WondersControllerTest < ActionDispatch::IntegrationTest
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

      test "lists all Wonders in the world with builder handle and hp_pct" do
        create(:wonder, kingdom: @kingdom, status: "construction", hp: 5_000)

        get "/v1/worlds/#{@world.id}/wonders", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["wonders"].size
        first = body["wonders"].first
        assert_equal "Alice", first["builder_handle"]
        assert_equal "construction", first["status"]
        assert_equal 50, first["hp_pct"]
      end

      test "returns empty list when no Wonders exist" do
        get "/v1/worlds/#{@world.id}/wonders", headers: auth_headers
        assert_response :success
        assert_equal [], response.parsed_body["wonders"]
      end

      test "non-member sees 404" do
        stranger = create(:player, email: "stranger@example.com")
        authenticate_as_player(stranger)
        get "/v1/worlds/#{@world.id}/wonders", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
