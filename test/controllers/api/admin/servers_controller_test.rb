require "test_helper"

module Api
  module Admin
    class ServersControllerTest < ActionDispatch::IntegrationTest
      test "GET /v1/admin/servers requires admin auth" do
        get "/v1/admin/servers"
        assert_response :unauthorized
      end

      test "GET /v1/admin/servers lists only servers the admin administers" do
        admin = create(:admin)
        mine_a = create(:server, owner: admin)
        mine_b = create(:server, owner: admin)
        _other = create(:server)
        authenticate_as_admin(admin)

        get "/v1/admin/servers", headers: auth_headers
        assert_response :success

        ids = response.parsed_body["servers"].map { |s| s["id"] }.sort
        assert_equal [ mine_a.id, mine_b.id ].sort, ids
      end

      test "POST /v1/admin/servers creates a server with the current admin as owner" do
        admin = create(:admin)
        authenticate_as_admin(admin)

        post "/v1/admin/servers", params: { name: "Acme Co" }, headers: auth_headers, as: :json
        assert_response :created

        body = response.parsed_body
        assert_equal "Acme Co", body["name"]
        assert_equal "acme-co", body["slug"]
        assert_equal admin.id, body["owner_admin_id"]
      end

      test "PATCH /v1/admin/servers/:id updates the world limits but not the slug" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        authenticate_as_admin(admin)

        patch "/v1/admin/servers/#{server.id}",
              params: { name: "Renamed", max_concurrent_worlds: 4, slug: "rogue" },
              headers: auth_headers, as: :json

        assert_response :success
        assert_equal "Renamed", response.parsed_body["name"]
        assert_equal 4, response.parsed_body["max_concurrent_worlds"]
        assert_not_equal "rogue", server.reload.slug
      end

      test "an admin cannot update a server they don't administer" do
        admin = create(:admin)
        other_server = create(:server)
        authenticate_as_admin(admin)

        patch "/v1/admin/servers/#{other_server.id}", params: { name: "x" }, headers: auth_headers, as: :json
        assert_response :not_found
      end

      test "a player-scope ApiKey is rejected" do
        player = create(:player)
        authenticate_as_player(player)

        get "/v1/admin/servers", headers: auth_headers
        assert_response :unauthorized
      end
    end
  end
end
