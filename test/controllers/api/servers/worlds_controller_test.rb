require "test_helper"

module Api
  module Servers
    class WorldsControllerTest < ActionDispatch::IntegrationTest
      test "GET /v1/servers/:id/worlds requires player auth" do
        server = create(:server)
        get "/v1/servers/#{server.id}/worlds"
        assert_response :unauthorized
      end

      test "GET /v1/servers/:id/worlds 404s when caller is not a member of the server" do
        server = create(:server)
        create(:world, server: server)
        stranger = create(:player)
        authenticate_as_player(stranger)

        get "/v1/servers/#{server.id}/worlds", headers: auth_headers
        assert_response :not_found
        assert_equal "not_found", response.parsed_body.dig("error", "code")
      end

      test "GET /v1/servers/:id/worlds 404s for a player-scope key on an unknown server" do
        player = create(:player)
        authenticate_as_player(player)

        get "/v1/servers/does-not-exist/worlds", headers: auth_headers
        assert_response :not_found
      end

      test "GET /v1/servers/:id/worlds rejects an admin-scope ApiKey" do
        admin  = create(:admin)
        server = create(:server, owner: admin)
        authenticate_as_admin(admin)

        get "/v1/servers/#{server.id}/worlds", headers: auth_headers
        assert_response :unauthorized
      end

      test "GET /v1/servers/:id/worlds returns every world on the server, ordered t0_at desc" do
        server = create(:server)
        player = create(:player)
        ServerMembership.create!(server: server, player: player)
        oldest = create(:world, server: server, t0_at: 5.days.ago)
        middle = create(:world, server: server, t0_at: 1.day.from_now)
        newest = create(:world, server: server, t0_at: 5.days.from_now)
        authenticate_as_player(player)

        get "/v1/servers/#{server.id}/worlds", headers: auth_headers
        assert_response :success

        ids = response.parsed_body["worlds"].map { |w| w["id"] }
        assert_equal [ newest.id, middle.id, oldest.id ], ids
      end

      test "GET /v1/servers/:id/worlds returns worlds of every status" do
        server = create(:server)
        player = create(:player)
        ServerMembership.create!(server: server, player: player)
        proposed  = create(:world,             server: server, t0_at: 5.days.from_now)
        grace     = create(:world, :grace,     server: server)
        active    = create(:world, :active,    server: server)
        archived  = create(:world, :archived,  server: server)
        cancelled = create(:world, :cancelled, server: server, t0_at: 10.days.ago)
        authenticate_as_player(player)

        get "/v1/servers/#{server.id}/worlds", headers: auth_headers
        assert_response :success

        returned_ids       = response.parsed_body["worlds"].map { |w| w["id"] }.sort
        returned_statuses  = response.parsed_body["worlds"].map { |w| w["status"] }.sort
        expected_ids       = [ proposed.id, grace.id, active.id, archived.id, cancelled.id ].sort
        expected_statuses  = %w[active archived cancelled grace proposed]

        assert_equal expected_ids, returned_ids
        assert_equal expected_statuses, returned_statuses
      end

      test "GET /v1/servers/:id/worlds does not leak worlds from other servers" do
        my_server    = create(:server)
        other_server = create(:server)
        player = create(:player)
        ServerMembership.create!(server: my_server, player: player)
        mine          = create(:world, server: my_server)
        _theirs       = create(:world, server: other_server)
        authenticate_as_player(player)

        get "/v1/servers/#{my_server.id}/worlds", headers: auth_headers
        assert_response :success

        ids = response.parsed_body["worlds"].map { |w| w["id"] }
        assert_equal [ mine.id ], ids
      end

      test "GET /v1/servers/:id/worlds returns the lean shape (no my_kingdom, region_count, kingdom_count, seed)" do
        server = create(:server)
        player = create(:player)
        ServerMembership.create!(server: server, player: player)
        world = create(:world, :archived, server: server)
        authenticate_as_player(player)

        get "/v1/servers/#{server.id}/worlds", headers: auth_headers
        assert_response :success

        entry = response.parsed_body["worlds"].first
        expected_keys = %w[
          id server_id name slug status min_players
          t0_at grace_closes_at archived_at cancelled_at wonder_name
        ].sort
        assert_equal expected_keys, entry.keys.sort

        assert_equal world.id, entry["id"]
        assert_equal "archived", entry["status"]
        assert_not_nil entry["archived_at"]
        assert_nil entry["cancelled_at"]
      end
    end
  end
end
