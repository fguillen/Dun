require "test_helper"

module Api
  module Servers
    class MeControllerTest < ActionDispatch::IntegrationTest
      setup do
        @server = create(:server)
        @player = create(:player, email: "alice@example.com")
        @profile = PlayerProfile.create!(server: @server, player: @player)
        ServerMembership.create!(server: @server, player: @player)
        authenticate_as_player(@player)
      end

      test "PATCH updates handle + real_name" do
        patch "/v1/servers/#{@server.id}/me",
              params: { handle: "IronFist", real_name: "Alice Example" },
              headers: auth_headers, as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal "IronFist", body["handle"]
        assert_equal "Alice Example", body["real_name"]
      end

      test "PATCH rejects a reserved handle with a 422 envelope" do
        patch "/v1/servers/#{@server.id}/me", params: { handle: "admin" }, headers: auth_headers, as: :json

        assert_response :unprocessable_entity
        assert_equal "invalid", response.parsed_body.dig("error", "code")
      end

      test "PATCH returns 422 handle_locked when the profile is locked" do
        PlayerProfile.any_instance.stubs(:locked?).returns(true)

        patch "/v1/servers/#{@server.id}/me", params: { handle: "TooLate" }, headers: auth_headers, as: :json

        assert_response :unprocessable_entity
        assert_equal "handle_locked", response.parsed_body.dig("error", "code")
      end

      test "an admin-scope key is rejected" do
        admin = create(:admin)
        authenticate_as_admin(admin)

        patch "/v1/servers/#{@server.id}/me", params: { handle: "X" }, headers: auth_headers, as: :json
        assert_response :unauthorized
      end

      test "GET returns the caller's own profile" do
        @profile.update!(handle: "IronFist", real_name: "Alice Example")

        get "/v1/servers/#{@server.id}/me", headers: auth_headers

        assert_response :success
        body = response.parsed_body
        assert_equal "IronFist", body["handle"]
        assert_equal "Alice Example", body["real_name"]
        assert body.key?("stats"), "expected stats in the response"
        assert body.key?("title"), "expected title in the response"
        assert body["joined_at"].present?, "expected joined_at in the response"
      end

      test "GET 404s with handle_not_set when no handle has been chosen" do
        get "/v1/servers/#{@server.id}/me", headers: auth_headers

        assert_response :not_found
        assert_equal "handle_not_set", response.parsed_body.dig("error", "code")
      end

      test "GET 404s with not_found when the player has no profile on this server" do
        @profile.destroy!

        get "/v1/servers/#{@server.id}/me", headers: auth_headers

        assert_response :not_found
        assert_equal "not_found", response.parsed_body.dig("error", "code")
      end

      test "GET 401s without authentication" do
        get "/v1/servers/#{@server.id}/me"
        assert_response :unauthorized
      end

      test "GET rejects an admin-scope key" do
        admin = create(:admin)
        authenticate_as_admin(admin)

        get "/v1/servers/#{@server.id}/me", headers: auth_headers
        assert_response :unauthorized
      end
    end
  end
end
