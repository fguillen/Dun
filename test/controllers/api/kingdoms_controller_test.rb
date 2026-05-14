require "test_helper"

module Api
  class KingdomsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create(:admin)
      @server = create(:server, owner: @admin)
      @player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: @server, player: @player)
      ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
      profile = create(:player_profile, server: @server, player: @player)

      @world = create(:world, :grace, server: @server)
      region = create(:region, world: @world)
      @kingdom = create(:kingdom, :with_buildings,
        world: @world, player_profile: profile, home_region: region)
      @kingdom.update!(stockpiles: {
        "gold" => 10_000, "wood" => 10_000, "stone" => 10_000, "iron" => 10_000,
        "checkpoint_at" => Time.current.iso8601
      })

      authenticate_as_player(@player)
    end

    test "GET /v1/kingdoms/:id returns materialized stockpiles, production, buildings" do
      get "/v1/kingdoms/#{@kingdom.id}", headers: auth_headers
      assert_response :success
      body = response.parsed_body

      assert_equal @kingdom.id, body["id"]
      assert body["stockpiles"].is_a?(Hash)
      assert_equal 4, body["stockpiles"].slice("gold", "wood", "stone", "iron").size
      assert body["production_rates"].is_a?(Hash)
      assert_equal Buildings::Catalog::KINDS.size, body["buildings"].size
      assert_equal [], body["in_progress_builds"]
    end

    test "GET /v1/kingdoms/:id resolves ripe build orders before serializing" do
      order = ::Buildings::Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
      order.update!(completes_at: 1.minute.ago)

      get "/v1/kingdoms/#{@kingdom.id}", headers: auth_headers
      assert_response :success
      assert_equal 2, @kingdom.buildings.find_by(kind: "quarry").reload.level
      assert_equal [], response.parsed_body["in_progress_builds"]
    end

    test "GET /v1/kingdoms/:id returns 404 for non-owner same-server profile" do
      stranger = create(:player)
      ServerMembership.create!(server: @server, player: stranger)
      create(:player_profile, server: @server, player: stranger)
      authenticate_as_player(stranger)
      get "/v1/kingdoms/#{@kingdom.id}", headers: auth_headers
      assert_response :not_found
    end

    test "GET /v1/kingdoms/:id returns 404 for non-server-member" do
      stranger = create(:player)
      authenticate_as_player(stranger)
      get "/v1/kingdoms/#{@kingdom.id}", headers: auth_headers
      assert_response :not_found
    end

    test "POST /v1/kingdoms/:id/build queues an upgrade" do
      post "/v1/kingdoms/#{@kingdom.id}/build",
        headers: auth_headers, as: :json,
        params: { building: "quarry", target_level: 2 }
      assert_response :created
      body = response.parsed_body
      assert_equal "quarry", body["kind"]
      assert_equal 2, body["target_level"]
    end

    test "POST /v1/kingdoms/:id/build returns 422 on insufficient resources" do
      @kingdom.update!(stockpiles: { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0, "checkpoint_at" => Time.current.iso8601 })
      post "/v1/kingdoms/#{@kingdom.id}/build",
        headers: auth_headers, as: :json,
        params: { building: "quarry", target_level: 2 }
      assert_response :unprocessable_entity
      assert_equal "insufficient_resources", response.parsed_body.dig("error", "code")
    end

    test "POST /v1/kingdoms/:id/build returns 422 on tier gate" do
      @kingdom.buildings.find_by(kind: "barracks").update!(level: 2)
      post "/v1/kingdoms/#{@kingdom.id}/build",
        headers: auth_headers, as: :json,
        params: { building: "stable", target_level: 1 }
      assert_response :unprocessable_entity
      assert_equal "tier_gate_unmet", response.parsed_body.dig("error", "code")
    end

    test "POST /v1/kingdoms/:id/build returns 422 on invalid target_level" do
      post "/v1/kingdoms/#{@kingdom.id}/build",
        headers: auth_headers, as: :json,
        params: { building: "quarry", target_level: 5 }
      assert_response :unprocessable_entity
      assert_equal "invalid_target_level", response.parsed_body.dig("error", "code")
    end

    test "POST /v1/kingdoms/:id/build returns 422 when world is archived" do
      @world.update!(status: "archived", archived_at: 1.hour.ago)
      post "/v1/kingdoms/#{@kingdom.id}/build",
        headers: auth_headers, as: :json,
        params: { building: "quarry", target_level: 2 }
      assert_response :unprocessable_entity
      assert_equal "world_not_buildable", response.parsed_body.dig("error", "code")
    end

    test "POST /v1/kingdoms/:id/build returns 422 on unknown building" do
      post "/v1/kingdoms/#{@kingdom.id}/build",
        headers: auth_headers, as: :json,
        params: { building: "castle", target_level: 1 }
      assert_response :unprocessable_entity
      assert_equal "unknown_building", response.parsed_body.dig("error", "code")
    end

    test "POST /v1/kingdoms/:id/build rejects non-owner" do
      stranger = create(:player)
      authenticate_as_player(stranger)
      post "/v1/kingdoms/#{@kingdom.id}/build",
        headers: auth_headers, as: :json,
        params: { building: "quarry", target_level: 2 }
      assert_response :not_found
    end

    test "admin-scope ApiKey is rejected" do
      authenticate_as_admin(@admin)
      get "/v1/kingdoms/#{@kingdom.id}", headers: auth_headers
      assert_response :unauthorized
    end
  end
end
