require "test_helper"

module Api
  module Worlds
    class ArchiveControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @world = create(:world, :active, server: @server)
        @region = create(:region, world: @world)
        @profile = create(:player_profile, server: @server)
        @kingdom = create(:kingdom, world: @world, player_profile: @profile, home_region: @region)

        @viewer = create(:player)
        ServerMembership.create!(server: @server, player: @viewer)
        create(:player_profile, server: @server, player: @viewer)
        authenticate_as_player(@viewer)
      end

      test "404 while the world is not yet archived" do
        get "/v1/worlds/#{@world.id}/archive", headers: auth_headers
        assert_response :not_found
      end

      test "returns frozen state once archived" do
        ::Rounds::End.call(world: @world, winning_kingdom: @kingdom, wonder_name: "sky_tower")
        get "/v1/worlds/#{@world.id}/archive", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal @world.id, body["world_id"]
        assert_equal @kingdom.id, body["winner_kingdom_id"]
        assert_equal "sky_tower", body["wonder_name"]
        assert body["frozen_state"]["regions"].is_a?(Array)
      end

      test "404 for non-members" do
        ::Rounds::End.call(world: @world, winning_kingdom: @kingdom, wonder_name: "sky_tower")
        stranger = create(:player, email: "stranger@example.com")
        authenticate_as_player(stranger)
        get "/v1/worlds/#{@world.id}/archive", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
