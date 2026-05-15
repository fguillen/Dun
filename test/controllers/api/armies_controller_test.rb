require "test_helper"

module Api
  class ArmiesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create(:admin)
      @server = create(:server, owner: @admin)
      @player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: @server, player: @player)
      ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
      profile = create(:player_profile, server: @server, player: @player)

      world = create(:world, :grace, server: @server)
      region = create(:region, world: world)
      @kingdom = create(:kingdom,
        world: world, player_profile: profile, home_region: region)
      @garrison = create(:army, :garrison,
        kingdom: @kingdom, location_region: region, composition: { "levy" => 10, "knight" => 5 })

      authenticate_as_player(@player)
    end

    test "GET show returns army detail for owner" do
      get "/v1/armies/#{@garrison.id}", headers: auth_headers
      assert_response :success
      body = response.parsed_body
      assert_equal Army::GARRISON_NAME, body["name"]
      assert_equal 10, body["composition"]["levy"]
      assert_equal 5, body["composition"]["knight"]
      assert_equal 10 * 50 + 5 * 80, body["total_capacity"]
    end

    test "GET show 404 for non-owner" do
      stranger = create(:player)
      authenticate_as_player(stranger)
      get "/v1/armies/#{@garrison.id}", headers: auth_headers
      assert_response :not_found
    end

    test "POST split creates a new army and shrinks the source" do
      post "/v1/armies/#{@garrison.id}/split",
        params: { units: { "levy" => 4, "knight" => 2 }, name: "Strike Force" },
        headers: auth_headers
      assert_response :created
      body = response.parsed_body
      assert_equal "Strike Force", body.dig("new", "name")
      assert_equal 6, body.dig("source", "composition", "levy")
      assert_equal 3, body.dig("source", "composition", "knight")
    end

    test "POST split 422 on insufficient units" do
      post "/v1/armies/#{@garrison.id}/split",
        params: { units: { "levy" => 99 }, name: "Strike Force" },
        headers: auth_headers
      assert_response :unprocessable_entity
      assert_equal "insufficient_units", response.parsed_body.dig("error", "code")
    end

    test "POST rename succeeds" do
      other = create(:army, kingdom: @kingdom, location_region: @kingdom.home_region, name: "Vanguard")
      post "/v1/armies/#{other.id}/rename",
        params: { name: "Phoenix" },
        headers: auth_headers
      assert_response :success
      assert_equal "Phoenix", response.parsed_body["name"]
    end

    test "POST rename 422 on collision" do
      a = create(:army, kingdom: @kingdom, location_region: @kingdom.home_region, name: "Vanguard")
      _b = create(:army, kingdom: @kingdom, location_region: @kingdom.home_region, name: "Phoenix")
      post "/v1/armies/#{a.id}/rename",
        params: { name: "Phoenix" },
        headers: auth_headers
      assert_response :unprocessable_entity
      assert_equal "name_taken", response.parsed_body.dig("error", "code")
    end

    test "POST merge sums into target and deletes source" do
      from = create(:army, kingdom: @kingdom, location_region: @kingdom.home_region,
        name: "Reserves", composition: { "levy" => 2, "archer" => 3 })
      post "/v1/armies/#{@garrison.id}/merge",
        params: { from_id: from.id },
        headers: auth_headers
      assert_response :success
      body = response.parsed_body
      assert_equal 12, body["composition"]["levy"]
      assert_equal 3, body["composition"]["archer"]
      assert_nil Army.find_by(id: from.id)
    end

    test "POST merge 422 on incompatible region" do
      elsewhere = create(:region, world: @kingdom.world)
      from = create(:army, kingdom: @kingdom, location_region: elsewhere, name: "Reserves")
      post "/v1/armies/#{@garrison.id}/merge",
        params: { from_id: from.id },
        headers: auth_headers
      assert_response :unprocessable_entity
      assert_equal "incompatible_armies", response.parsed_body.dig("error", "code")
    end
  end
end
