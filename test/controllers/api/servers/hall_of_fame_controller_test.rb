require "test_helper"

module Api
  module Servers
    class HallOfFameControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @player = create(:player)
        ServerMembership.create!(server: @server, player: @player)
        create(:player_profile, server: @server, player: @player)
        authenticate_as_player(@player)

        @champion_profile = create(:player_profile, server: @server, handle: "winner")
        @champion_profile.stats.update!(rounds_won: 4, wonders_destroyed: 1)
        Leaderboards::Recompute.call(server: @server)
      end

      test "members can read all four leaderboards" do
        get "/v1/servers/#{@server.id}/hall-of-fame", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal LeaderboardSnapshot::KINDS.sort, body["leaderboards"].keys.sort
        champions = body["leaderboards"]["champions"]
        assert_equal "winner", champions["entries"].first["handle"]
        assert_equal 4, champions["entries"].first["score"]
      end

      test "kind filter limits the response" do
        get "/v1/servers/#{@server.id}/hall-of-fame?kind=champions", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal [ "champions" ], body["leaderboards"].keys
      end

      test "rejects non-members" do
        stranger = create(:player, email: "stranger@example.com")
        authenticate_as_player(stranger)
        get "/v1/servers/#{@server.id}/hall-of-fame", headers: auth_headers
        assert_response :forbidden
      end

      test "rejects invalid kinds" do
        get "/v1/servers/#{@server.id}/hall-of-fame?kind=bogus", headers: auth_headers
        assert_response :unprocessable_entity
      end
    end
  end
end
