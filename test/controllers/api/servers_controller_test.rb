require "test_helper"

module Api
  class ServersControllerTest < ActionDispatch::IntegrationTest
    test "GET /v1/servers requires auth" do
      get "/v1/servers"
      assert_response :unauthorized
    end

    test "GET /v1/servers lists eligible + member servers, marking membership" do
      member_server = create(:server)
      eligible_server = create(:server)
      _other_server = create(:server) # neither eligible nor member

      player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: member_server, player: player)
      create(:server_access, server: eligible_server, kind: "domain", value: "*@example.com")

      authenticate_as_player(player)

      get "/v1/servers", headers: auth_headers
      assert_response :success

      servers = response.parsed_body["servers"]
      ids = servers.map { |s| s["id"] }.sort
      assert_equal [ member_server.id, eligible_server.id ].sort, ids

      member_entry = servers.find { |s| s["id"] == member_server.id }
      eligible_entry = servers.find { |s| s["id"] == eligible_server.id }
      assert member_entry["member"]
      assert_not eligible_entry["member"]
    end

    test "POST /v1/servers/:id/join admits an eligible player" do
      server = create(:server)
      create(:server_access, server: server, kind: "domain", value: "*@example.com")
      player = create(:player, email: "alice@example.com")
      authenticate_as_player(player)

      post "/v1/servers/#{server.id}/join", headers: auth_headers, as: :json
      assert_response :created
      assert ServerMembership.exists?(server: server, player: player)
    end

    test "POST /v1/servers/:id/join 403s for an ineligible player" do
      server = create(:server)
      player = create(:player, email: "alice@nowhere.com")
      authenticate_as_player(player)

      post "/v1/servers/#{server.id}/join", headers: auth_headers, as: :json
      assert_response :forbidden
      assert_equal "forbidden", response.parsed_body.dig("error", "code")
    end

    test "POST /v1/servers/:id/join is idempotent" do
      server = create(:server)
      create(:server_access, server: server, kind: "domain", value: "*@example.com")
      player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: server, player: player)
      authenticate_as_player(player)

      assert_no_difference -> { ServerMembership.count } do
        post "/v1/servers/#{server.id}/join", headers: auth_headers, as: :json
      end
      assert_response :created
    end

    test "an admin-scope key is rejected" do
      admin = create(:admin)
      authenticate_as_admin(admin)

      get "/v1/servers", headers: auth_headers
      assert_response :unauthorized
    end
  end
end
