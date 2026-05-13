require "test_helper"

module Api
  module Auth
    class KeysControllerTest < ActionDispatch::IntegrationTest
      test "GET /v1/auth/keys requires authentication" do
        get "/v1/auth/keys"
        assert_response :unauthorized
        assert_equal "unauthorized", response.parsed_body.dig("error", "code")
      end

      test "GET /v1/auth/keys lists the current player's keys and marks the current one" do
        player = create(:player)
        _key1, _raw1 = ApiKey.generate_for(owner: player, name: "laptop")
        raw_current = authenticate_as_player(player)
        current_key = ApiKey.find_by(token_digest: Digest::SHA256.hexdigest(raw_current))

        get "/v1/auth/keys", headers: auth_headers

        assert_response :success
        body = response.parsed_body
        assert_equal 2, body["keys"].size
        current_entry = body["keys"].find { |k| k["id"] == current_key.id }
        assert current_entry["current"]
      end

      test "DELETE /v1/auth/keys/:id revokes the key" do
        player = create(:player)
        key, _raw = ApiKey.generate_for(owner: player, name: "laptop")
        authenticate_as_player(player)

        delete "/v1/auth/keys/#{key.id}", headers: auth_headers
        assert_response :no_content
        assert key.reload.revoked_at.present?
      end

      test "an admin-scope key cannot list or revoke player keys" do
        admin = create(:admin)
        authenticate_as_admin(admin)

        get "/v1/auth/keys", headers: auth_headers
        assert_response :unauthorized
      end
    end
  end
end
