require "test_helper"

module Api
  module Auth
    class AccountControllerTest < ActionDispatch::IntegrationTest
      test "DELETE /v1/auth/account requires authentication" do
        delete "/v1/auth/account"
        assert_response :unauthorized
      end

      test "DELETE /v1/auth/account tombstones the player and revokes the calling key" do
        player = create(:player, email: "p@example.com", name: "P")
        raw = authenticate_as_player(player)

        delete "/v1/auth/account", headers: auth_headers
        assert_response :no_content

        player.reload
        assert_not_nil player.deleted_at

        get "/v1/auth/keys", headers: { "Authorization" => "Bearer #{raw}" }
        assert_response :unauthorized
      end

      test "an admin-scope key cannot delete a player account" do
        admin = create(:admin)
        authenticate_as_admin(admin)
        delete "/v1/auth/account", headers: auth_headers
        assert_response :unauthorized
      end
    end
  end
end
