require "test_helper"

module Api
  class WorldsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create(:admin)
      @server = create(:server, owner: @admin)
      @player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: @server, player: @player)
      ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
      @world = create(:world, server: @server, status: "proposed", min_players: 4, t0_at: 1.day.from_now)
      authenticate_as_player(@player)
    end

    test "GET /v1/worlds/:id returns 404 to non-members" do
      stranger = create(:player)
      authenticate_as_player(stranger)
      get "/v1/worlds/#{@world.id}", headers: auth_headers
      assert_response :not_found
    end

    test "GET /v1/worlds/:id returns the world to server members" do
      get "/v1/worlds/#{@world.id}", headers: auth_headers
      assert_response :success
      assert_equal @world.id, response.parsed_body["id"]
      assert_equal "proposed", response.parsed_body["status"]
    end

    test "POST /v1/worlds/:id/join creates a stub kingdom for a proposed world" do
      post "/v1/worlds/#{@world.id}/join", headers: auth_headers, as: :json
      assert_response :created
      body = response.parsed_body
      assert_equal @world.id, body["world_id"]
      assert_nil body["home_region_id"]
    end

    test "POST /v1/worlds/:id/join rejects a player not admitted to the server" do
      stranger = create(:player, email: "rando@nope.example")
      ServerMembership.create!(server: @server, player: stranger)
      authenticate_as_player(stranger)
      post "/v1/worlds/#{@world.id}/join", headers: auth_headers, as: :json
      assert_response :forbidden
    end

    test "POST /v1/worlds/:id/join returns 422 for a closed (active) world" do
      @world.update!(status: "active", grace_closes_at: 1.hour.ago, t0_at: 4.days.ago)
      post "/v1/worlds/#{@world.id}/join", headers: auth_headers, as: :json
      assert_response :unprocessable_entity
      assert_equal "world_not_joinable", response.parsed_body.dig("error", "code")
    end

    test "GET /v1/worlds/:id/map lists regions with terrain, adjacency, nodes" do
      grace_world = create(:world, :grace, server: @server, seed: "0000000000002f35", min_players: 12)
      MapGeneration::Generate.call(world: grace_world, players_count: 12)

      get "/v1/worlds/#{grace_world.id}/map", headers: auth_headers
      assert_response :success
      regions = response.parsed_body["regions"]
      assert_equal 36, regions.size
      sample = regions.first
      assert_includes Region::TERRAINS, sample["terrain"]
      assert sample.key?("adjacency")
      assert sample.key?("nodes")
      assert sample.key?("owner_kingdom_id")
      assert sample.key?("owner_handle")
      assert_nil sample["owner_kingdom_id"], "fresh map has no claimed regions"
    end

    test "GET /v1/worlds/:id/map exposes region ownership and owner handle" do
      world = create(:world, :grace, server: @server)
      wild_region  = create(:region, world: world)
      owned_region = create(:region, world: world)
      kingdom = create(:kingdom, world: world, home_region: owned_region)
      create(:node, region: owned_region, is_home_hoard: true, owner_kingdom_id: kingdom.id)
      create(:node, region: wild_region)

      get "/v1/worlds/#{world.id}/map", headers: auth_headers
      assert_response :success
      regions = response.parsed_body["regions"].index_by { |r| r["id"] }

      assert_nil regions[wild_region.id]["owner_kingdom_id"]
      assert_nil regions[wild_region.id]["owner_handle"]
      assert_equal kingdom.id, regions[owned_region.id]["owner_kingdom_id"]
      assert_equal kingdom.player_profile.handle, regions[owned_region.id]["owner_handle"]
    end

    test "GET /v1/worlds/:id/map shows region ownership and node owner for a captured non-home-hoard node" do
      world = create(:world, :grace, server: @server)
      region = create(:region, world: world)
      kingdom = create(:kingdom, world: world)
      node = create(:node, region: region, resource: "iron", owner_kingdom_id: kingdom.id)

      get "/v1/worlds/#{world.id}/map", headers: auth_headers
      assert_response :success
      region_body = response.parsed_body["regions"].find { |r| r["id"] == region.id }

      assert_equal kingdom.id, region_body["owner_kingdom_id"]
      assert_equal kingdom.player_profile.handle, region_body["owner_handle"]

      node_body = region_body["nodes"].find { |n| n["id"] == node.id }
      assert_equal kingdom.id, node_body["owner_kingdom_id"]
      assert_equal kingdom.player_profile.handle, node_body["owner_handle"]
    end

    test "GET /v1/worlds/:id/map lists visible armies per region with composition and mine flag" do
      world = create(:world, :grace, server: @server)
      region_a = create(:region, world: world)
      region_b = create(:region, world: world)

      mine = create(:kingdom, world: world, home_region: region_a,
        player_profile: create(:player_profile, server: @server, player: @player))
      theirs = create(:kingdom, world: world, home_region: region_b,
        player_profile: create(:player_profile, server: @server))

      my_army = create(:army, kingdom: mine, location_region: region_a, name: "Mine",
        composition: { "levy" => 25, "archer" => 10 })
      their_army = create(:army, :marching, kingdom: theirs, location_region: region_a, name: "Theirs",
        composition: { "knight" => 3 })

      get "/v1/worlds/#{world.id}/map", headers: auth_headers
      assert_response :success
      regions = response.parsed_body["regions"].index_by { |r| r["id"] }

      armies = regions[region_a.id]["visible_armies"].index_by { |a| a["army_id"] }
      assert_equal 2, armies.size

      assert_equal true, armies[my_army.id]["mine"]
      assert_equal "home", armies[my_army.id]["status"]
      assert_equal({ "levy" => 25, "archer" => 10 }, armies[my_army.id]["composition"])
      assert_equal mine.player_profile.handle, armies[my_army.id]["owner_handle"]

      assert_equal false, armies[their_army.id]["mine"]
      assert_equal "marching", armies[their_army.id]["status"]

      assert_equal [], regions[region_b.id]["visible_armies"]
    end

    test "GET /v1/worlds/:id/regions/:id returns nodes, ruin, adjacency" do
      grace_world = create(:world, :grace, server: @server, seed: "0000000000002f35", min_players: 12)
      MapGeneration::Generate.call(world: grace_world, players_count: 12)
      region = grace_world.regions.first

      get "/v1/worlds/#{grace_world.id}/regions/#{region.id}", headers: auth_headers
      assert_response :success
      body = response.parsed_body
      assert_equal region.id, body["id"]
      assert body.key?("adjacency")
      assert body.key?("nodes")
      assert body.key?("owner_kingdom_id")
      assert body.key?("owner_handle")
    end

    test "GET /v1/worlds/:id/regions/:id exposes owner handle on region and nodes" do
      world = create(:world, :grace, server: @server)
      region = create(:region, world: world)
      kingdom = create(:kingdom, world: world, home_region: region)
      create(:node, region: region, is_home_hoard: true, owner_kingdom_id: kingdom.id)
      create(:node, region: region)

      get "/v1/worlds/#{world.id}/regions/#{region.id}", headers: auth_headers
      assert_response :success
      body = response.parsed_body

      assert_equal kingdom.id, body["owner_kingdom_id"]
      assert_equal kingdom.player_profile.handle, body["owner_handle"]

      home = body["nodes"].find { |n| n["is_home_hoard"] }
      wild = body["nodes"].find { |n| !n["is_home_hoard"] }
      assert_equal kingdom.player_profile.handle, home["owner_handle"]
      assert_nil wild["owner_kingdom_id"]
      assert_nil wild["owner_handle"]
    end

    test "GET /v1/worlds/:id/regions/:id reflects a captured non-home-hoard node as the region owner" do
      world = create(:world, :grace, server: @server)
      region = create(:region, world: world)
      kingdom = create(:kingdom, world: world)
      create(:node, region: region, resource: "iron", owner_kingdom_id: kingdom.id)

      get "/v1/worlds/#{world.id}/regions/#{region.id}", headers: auth_headers
      assert_response :success
      body = response.parsed_body

      assert_equal kingdom.id, body["owner_kingdom_id"]
      assert_equal kingdom.player_profile.handle, body["owner_handle"]
    end

    test "GET /v1/worlds/:id/ruins lists ruins on the world" do
      grace_world = create(:world, :grace, server: @server, seed: "0000000000003fc3", min_players: 16)
      MapGeneration::Generate.call(world: grace_world, players_count: 16)

      get "/v1/worlds/#{grace_world.id}/ruins", headers: auth_headers
      assert_response :success
      assert response.parsed_body["ruins"].is_a?(Array)
    end

    test "GET /v1/worlds/:id/nodes lists nodes on the world" do
      grace_world = create(:world, :grace, server: @server, seed: "0000000000003fc3", min_players: 16)
      MapGeneration::Generate.call(world: grace_world, players_count: 16)

      get "/v1/worlds/#{grace_world.id}/nodes", headers: auth_headers
      assert_response :success
      nodes = response.parsed_body["nodes"]
      assert nodes.is_a?(Array)
      assert nodes.any?
      sample = nodes.first
      %w[id region_id region_name resource tier base_rate is_home_hoard owner_kingdom_id owner_handle garrison].each do |key|
        assert sample.key?(key), "expected node serialization to include #{key}"
      end
    end

    test "GET /v1/worlds/:id/nodes exposes owner_handle for captured nodes" do
      world = create(:world, :grace, server: @server)
      region = create(:region, world: world)
      kingdom = create(:kingdom, world: world, home_region: region)
      captured = create(:node, region: region, owner_kingdom_id: kingdom.id)
      wild = create(:node, region: region)

      get "/v1/worlds/#{world.id}/nodes", headers: auth_headers
      assert_response :success
      nodes = response.parsed_body["nodes"].index_by { |n| n["id"] }
      assert_equal kingdom.player_profile.handle, nodes[captured.id]["owner_handle"]
      assert_nil nodes[wild.id]["owner_handle"]
    end

    test "GET /v1/worlds/:id/nodes/:id returns a single node" do
      grace_world = create(:world, :grace, server: @server, seed: "0000000000003fc3", min_players: 16)
      MapGeneration::Generate.call(world: grace_world, players_count: 16)
      node = grace_world.nodes.first

      get "/v1/worlds/#{grace_world.id}/nodes/#{node.id}", headers: auth_headers
      assert_response :success
      assert_equal node.id, response.parsed_body.dig("node", "id")
    end

    test "GET /v1/worlds/:id/nodes/:id returns 404 for an unknown node" do
      grace_world = create(:world, :grace, server: @server, seed: "0000000000003fc3", min_players: 16)
      MapGeneration::Generate.call(world: grace_world, players_count: 16)

      get "/v1/worlds/#{grace_world.id}/nodes/does_not_exist", headers: auth_headers
      assert_response :not_found
    end

    test "non-member receives 404 on map/region/ruins/nodes endpoints" do
      stranger = create(:player)
      authenticate_as_player(stranger)

      get "/v1/worlds/#{@world.id}/map", headers: auth_headers
      assert_response :not_found

      get "/v1/worlds/#{@world.id}/ruins", headers: auth_headers
      assert_response :not_found

      get "/v1/worlds/#{@world.id}/nodes", headers: auth_headers
      assert_response :not_found
    end

    test "admin-scope ApiKey is rejected" do
      authenticate_as_admin(@admin)
      get "/v1/worlds/#{@world.id}", headers: auth_headers
      assert_response :unauthorized
    end
  end
end
