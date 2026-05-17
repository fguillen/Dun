require "test_helper"

module Api
  module Kingdoms
    class BuildOrdersControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @player = create(:player, email: "alice@example.com")
        ServerMembership.create!(server: @server, player: @player)
        ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
        profile = create(:player_profile, server: @server, player: @player)

        world = create(:world, :grace, server: @server)
        region = create(:region, world: world)
        @kingdom = create(:kingdom, :with_buildings,
          world: world, player_profile: profile, home_region: region)
        @kingdom.update!(stockpiles: {
          "gold" => 10_000, "wood" => 10_000, "stone" => 10_000, "iron" => 10_000,
          "checkpoint_at" => Time.current.iso8601
        })

        @order = ::Buildings::Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
        authenticate_as_player(@player)
      end

      test "DELETE cancels an in-progress build order with 75% refund" do
        gold_before = @kingdom.reload.stockpiles["gold"]
        cost = ::Buildings::CostFor.call(kind: "quarry", level: 2)

        delete "/v1/kingdoms/#{@kingdom.id}/build/#{@order.id}", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_not_nil body["cancelled_at"]

        @kingdom.reload
        assert_equal gold_before + (cost["gold"] * 0.75).floor, @kingdom.stockpiles["gold"]
      end

      test "DELETE returns 404 for an order on another kingdom" do
        other_kingdom = create(:kingdom, :with_buildings,
          world: @kingdom.world,
          player_profile: create(:player_profile, server: @server))
        other_kingdom.update!(stockpiles: {
          "gold" => 10_000, "wood" => 10_000, "stone" => 10_000, "iron" => 10_000,
          "checkpoint_at" => Time.current.iso8601
        })
        foreign_order = ::Buildings::Queue.call(kingdom: other_kingdom, kind: "quarry", target_level: 2)

        delete "/v1/kingdoms/#{@kingdom.id}/build/#{foreign_order.id}", headers: auth_headers
        assert_response :not_found
      end

      test "DELETE returns 422 when order is already resolved" do
        @order.update!(completed_at: Time.current)
        delete "/v1/kingdoms/#{@kingdom.id}/build/#{@order.id}", headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "build_order_already_resolved", response.parsed_body.dig("error", "code")
      end

      test "DELETE rejects non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        delete "/v1/kingdoms/#{@kingdom.id}/build/#{@order.id}", headers: auth_headers
        assert_response :not_found
      end

      test "GET preview returns next-level cost, duration, and affordability" do
        get "/v1/kingdoms/#{@kingdom.id}/build/preview",
          params: { building: "barracks" }, headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal "barracks", body["kind"]
        assert_equal 1, body["current_level"]
        assert_equal 2, body["target_level"]
        assert_equal false, body["at_max_level"]
        expected_cost = ::Buildings::CostFor.call(kind: "barracks", level: 2)
        assert_equal expected_cost, body["cost"]
        assert_equal true, body["affordable"]
        assert_equal({ "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 }, body["missing"])
        assert_equal true, body["tier_gates_met"]
        assert body["duration_seconds"] > 0
      end

      test "GET preview surfaces unmet tier gates" do
        @kingdom.buildings.find_by(kind: "barracks").update!(level: 3)
        @kingdom.buildings.find_by(kind: "iron_mine").update!(level: 4)
        get "/v1/kingdoms/#{@kingdom.id}/build/preview",
          params: { building: "siege_workshop" }, headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal false, body["tier_gates_met"]
        kinds = body["tier_gates_unmet"].map { |g| g["kind"] }
        assert_includes kinds, "barracks"
        assert_includes kinds, "iron_mine"
      end

      test "GET preview returns 422 for unknown building" do
        get "/v1/kingdoms/#{@kingdom.id}/build/preview",
          params: { building: "castle" }, headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "unknown_building", response.parsed_body.dig("error", "code")
      end

      test "GET preview returns 404 for non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/build/preview",
          params: { building: "barracks" }, headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
