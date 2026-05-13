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
    end
  end
end
