require "test_helper"

module Api
  module Servers
    class PlayersControllerTest < ActionDispatch::IntegrationTest
      test "GET returns the target profile when caller is a member of the server" do
        server = create(:server)
        viewer = create(:player, email: "viewer@example.com")
        target = create(:player, email: "target@example.com")
        ServerMembership.create!(server: server, player: viewer)
        PlayerProfile.create!(server: server, player: target, handle: "IronFist", real_name: "Target Name")
        authenticate_as_player(viewer)

        get "/v1/servers/#{server.id}/players/IronFist", headers: auth_headers
        assert_response :success

        body = response.parsed_body
        assert_equal "IronFist", body["handle"]
        assert_equal "Target Name", body["real_name"]
      end

      test "GET 403s when caller is not a member of the server" do
        server = create(:server)
        viewer = create(:player)
        authenticate_as_player(viewer)

        get "/v1/servers/#{server.id}/players/anyone", headers: auth_headers
        assert_response :forbidden
      end

      test "GET 404s when no such handle exists on the server" do
        server = create(:server)
        viewer = create(:player)
        ServerMembership.create!(server: server, player: viewer)
        authenticate_as_player(viewer)

        get "/v1/servers/#{server.id}/players/nobody", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
