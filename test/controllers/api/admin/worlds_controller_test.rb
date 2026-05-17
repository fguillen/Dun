require "test_helper"

module Api
  module Admin
    class WorldsControllerTest < ActionDispatch::IntegrationTest
      test "GET /v1/admin/worlds/:id requires admin auth" do
        world = create(:world)
        get "/v1/admin/worlds/#{world.id}"
        assert_response :unauthorized
      end

      test "GET /v1/admin/worlds/:id returns the world for an administering admin" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        world = create(:world, server: server)
        authenticate_as_admin(admin)

        get "/v1/admin/worlds/#{world.id}", headers: auth_headers
        assert_response :success
        assert_equal world.id, response.parsed_body["id"]
        assert_equal "proposed", response.parsed_body["status"]
      end

      test "GET /v1/admin/worlds/:id returns 404 for a non-administering admin" do
        admin = create(:admin)
        other_world = create(:world)
        authenticate_as_admin(admin)

        get "/v1/admin/worlds/#{other_world.id}", headers: auth_headers
        assert_response :not_found
      end

      test "PATCH /v1/admin/worlds/:id updates whitelisted attrs" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        world = create(:world, server: server, min_players: 4, name: "Old")
        authenticate_as_admin(admin)

        patch "/v1/admin/worlds/#{world.id}",
              params: { name: "New", min_players: 8 },
              headers: auth_headers, as: :json
        assert_response :success
        assert_equal "New", response.parsed_body["name"]
        assert_equal 8, response.parsed_body["min_players"]
      end

      test "PATCH returns 422 once the world is past proposed" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        world = create(:world, :grace, server: server)
        authenticate_as_admin(admin)

        patch "/v1/admin/worlds/#{world.id}",
              params: { name: "Late" },
              headers: auth_headers, as: :json
        assert_response :unprocessable_entity
        assert_equal "world_not_configurable", response.parsed_body.dig("error", "code")
      end

      test "POST /v1/admin/worlds/:id/cancel cancels a proposed world" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        world = create(:world, server: server)
        authenticate_as_admin(admin)

        post "/v1/admin/worlds/#{world.id}/cancel", headers: auth_headers, as: :json
        assert_response :success
        assert_equal "cancelled", response.parsed_body["status"]
        assert_not_nil response.parsed_body["cancelled_at"]
      end

      test "POST /v1/admin/worlds/:id/cancel returns 422 on a non-proposed world" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        world = create(:world, :active, server: server)
        authenticate_as_admin(admin)

        post "/v1/admin/worlds/#{world.id}/cancel", headers: auth_headers, as: :json
        assert_response :unprocessable_entity
        assert_equal "world_not_cancellable", response.parsed_body.dig("error", "code")
      end

      test "POST /v1/admin/worlds/:id/start force-starts a proposed world" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        world = create(:world,
                       server: server,
                       min_players: 24,
                       t0_at: 7.days.from_now)
        authenticate_as_admin(admin)
        MapGeneration::Generate.stubs(:call)

        post "/v1/admin/worlds/#{world.id}/start", headers: auth_headers, as: :json
        assert_response :success
        assert_equal "grace", response.parsed_body["status"]
        assert_not_nil response.parsed_body["grace_closes_at"]
      end

      test "POST /v1/admin/worlds/:id/start returns 404 for a non-administering admin" do
        admin = create(:admin)
        other_world = create(:world)
        authenticate_as_admin(admin)

        post "/v1/admin/worlds/#{other_world.id}/start", headers: auth_headers, as: :json
        assert_response :not_found
      end

      test "POST /v1/admin/worlds/:id/start returns 422 on a non-proposed world" do
        admin = create(:admin)
        server = create(:server, owner: admin)
        world = create(:world, :active, server: server)
        authenticate_as_admin(admin)

        post "/v1/admin/worlds/#{world.id}/start", headers: auth_headers, as: :json
        assert_response :unprocessable_entity
        assert_equal "world_not_startable", response.parsed_body.dig("error", "code")
      end

      test "POST /v1/admin/worlds/:id/start rejects a player-scope ApiKey" do
        player = create(:player)
        world = create(:world)
        authenticate_as_player(player)

        post "/v1/admin/worlds/#{world.id}/start", headers: auth_headers, as: :json
        assert_response :unauthorized
      end

      test "PATCH rejects a player-scope ApiKey" do
        player = create(:player)
        world = create(:world)
        authenticate_as_player(player)

        patch "/v1/admin/worlds/#{world.id}", params: { name: "x" }, headers: auth_headers, as: :json
        assert_response :unauthorized
      end
    end
  end
end
