require "test_helper"

module Api
  module Admin
    module Servers
      class WorldsControllerTest < ActionDispatch::IntegrationTest
        test "GET /v1/admin/servers/:server_id/worlds requires admin auth" do
          server = create(:server)
          get "/v1/admin/servers/#{server.id}/worlds"
          assert_response :unauthorized
        end

        test "GET /v1/admin/servers/:server_id/worlds lists worlds on the administered server" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          mine_a = create(:world, server: server, t0_at: 1.day.from_now)
          mine_b = create(:world, server: server, t0_at: 2.days.from_now)
          _other_server_world = create(:world)
          authenticate_as_admin(admin)

          get "/v1/admin/servers/#{server.id}/worlds", headers: auth_headers
          assert_response :success

          ids = response.parsed_body["worlds"].map { |w| w["id"] }.sort
          assert_equal [ mine_a.id, mine_b.id ].sort, ids
        end

        test "non-administering admin cannot list worlds (404)" do
          admin = create(:admin)
          other_server = create(:server)
          authenticate_as_admin(admin)

          get "/v1/admin/servers/#{other_server.id}/worlds", headers: auth_headers
          assert_response :not_found
          assert_equal "not_found", response.parsed_body.dig("error", "code")
          assert_equal "Resource not found", response.parsed_body.dig("error", "message")
          refute_match(/ServerAdminship|WHERE|admin_id/i, response.parsed_body.dig("error", "message"),
                       "AR internals must not leak into the error envelope")
        end

        test "POST /v1/admin/servers/:server_id/worlds creates a proposed world" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          authenticate_as_admin(admin)

          t0 = 1.day.from_now
          post "/v1/admin/servers/#{server.id}/worlds",
               params: { name: "Spring 2026", min_players: 4, t0_at: t0.iso8601 },
               headers: auth_headers, as: :json

          assert_response :created
          body = response.parsed_body
          assert_equal "Spring 2026", body["name"]
          assert_equal "spring-2026", body["slug"]
          assert_equal "proposed", body["status"]
          assert_equal 4, body["min_players"]
          assert_match(/\A[0-9a-f]{16}\z/, body["seed"])
        end

        test "POST requires t0_at, min_players, name" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          authenticate_as_admin(admin)

          post "/v1/admin/servers/#{server.id}/worlds",
               params: { name: "X" },
               headers: auth_headers, as: :json
          assert_response :unprocessable_entity
        end

        test "POST returns 422 when the concurrent world limit is reached" do
          admin = create(:admin)
          server = create(:server, owner: admin, max_concurrent_worlds: 1)
          create(:world, server: server)
          authenticate_as_admin(admin)

          post "/v1/admin/servers/#{server.id}/worlds",
               params: { name: "Second", min_players: 4, t0_at: 1.day.from_now.iso8601 },
               headers: auth_headers, as: :json

          assert_response :unprocessable_entity
          assert_equal "concurrent_world_limit_reached", response.parsed_body.dig("error", "code")
        end

        test "POST rejects a player-scope ApiKey" do
          player = create(:player)
          server = create(:server)
          authenticate_as_player(player)

          post "/v1/admin/servers/#{server.id}/worlds",
               params: { name: "x", min_players: 4, t0_at: 1.day.from_now.iso8601 },
               headers: auth_headers, as: :json
          assert_response :unauthorized
        end
      end
    end
  end
end
