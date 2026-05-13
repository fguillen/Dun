require "test_helper"

module Api
  module Admin
    module Auth
      class KeysControllerTest < ActionDispatch::IntegrationTest
        test "GET /v1/admin/auth/keys requires admin authentication" do
          get "/v1/admin/auth/keys"
          assert_response :unauthorized
        end

        test "an admin lists their own admin-scope keys" do
          admin = create(:admin)
          authenticate_as_admin(admin)

          get "/v1/admin/auth/keys", headers: auth_headers
          assert_response :success
          assert_equal 1, response.parsed_body["keys"].size
        end

        test "a player-scope key cannot access admin keys" do
          player = create(:player)
          authenticate_as_player(player)

          get "/v1/admin/auth/keys", headers: auth_headers
          assert_response :unauthorized
        end

        test "DELETE /v1/admin/auth/keys/:id revokes the admin key" do
          admin = create(:admin)
          key, _raw = ApiKey.generate_for(owner: admin, name: "console")
          authenticate_as_admin(admin)

          delete "/v1/admin/auth/keys/#{key.id}", headers: auth_headers
          assert_response :no_content
          assert key.reload.revoked_at.present?
        end
      end
    end
  end
end
