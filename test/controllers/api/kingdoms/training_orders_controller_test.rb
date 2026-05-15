require "test_helper"

module Api
  module Kingdoms
    class TrainingOrdersControllerTest < ActionDispatch::IntegrationTest
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
        @kingdom.buildings.find_by(kind: "barracks").update!(level: 1)
        @kingdom.buildings.find_by(kind: "warehouse").update!(level: 5)
        @kingdom.update!(stockpiles: {
          "gold" => 50_000, "wood" => 50_000, "stone" => 50_000, "iron" => 50_000,
          "checkpoint_at" => Time.current.iso8601
        })
        authenticate_as_player(@player)
      end

      test "POST happy path returns 201 and deducts cost" do
        gold_before = @kingdom.stockpiles["gold"]
        post "/v1/kingdoms/#{@kingdom.id}/train",
          params: { building: "barracks", unit: "levy", count: 3 },
          headers: auth_headers
        assert_response :created
        body = response.parsed_body
        assert_equal "levy", body["unit"]
        assert_equal 3, body["count"]
        assert_equal "barracks", body["building_kind"]

        @kingdom.reload
        cost = ::Units::Catalog.cost_for("levy")
        assert_equal gold_before - cost["gold"] * 3, @kingdom.stockpiles["gold"]
      end

      test "POST 422 on insufficient resources" do
        @kingdom.update!(stockpiles: {
          "gold" => 1, "wood" => 1, "stone" => 1, "iron" => 1,
          "checkpoint_at" => Time.current.iso8601
        })
        post "/v1/kingdoms/#{@kingdom.id}/train",
          params: { building: "barracks", unit: "levy", count: 1 },
          headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "insufficient_resources", response.parsed_body.dig("error", "code")
      end

      test "POST 422 on unknown unit" do
        post "/v1/kingdoms/#{@kingdom.id}/train",
          params: { building: "barracks", unit: "ninja", count: 1 },
          headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "unknown_unit", response.parsed_body.dig("error", "code")
      end

      test "POST 422 on building missing (level 0)" do
        @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 0)
        post "/v1/kingdoms/#{@kingdom.id}/train",
          params: { building: "siege_workshop", unit: "catapult", count: 1 },
          headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "building_missing", response.parsed_body.dig("error", "code")
      end

      test "POST 422 on unit/building mismatch" do
        @kingdom.buildings.find_by(kind: "stable").update!(level: 1)
        post "/v1/kingdoms/#{@kingdom.id}/train",
          params: { building: "stable", unit: "levy", count: 1 },
          headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "unit_not_trainable_here", response.parsed_body.dig("error", "code")
      end

      test "DELETE refunds 75% and returns 200" do
        order = ::Training::Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 4)
        gold_after = @kingdom.reload.stockpiles["gold"]

        delete "/v1/kingdoms/#{@kingdom.id}/train/#{order.id}", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_not_nil body["cancelled_at"]

        cost = ::Units::Catalog.cost_for("levy")
        @kingdom.reload
        expected_refund = (cost["gold"] * 4 * ::Training::Cancel::REFUND_RATIO).floor
        assert_equal gold_after + expected_refund, @kingdom.stockpiles["gold"]
      end

      test "DELETE 422 when already resolved" do
        order = ::Training::Queue.call(kingdom: @kingdom, building_kind: "barracks", unit: "levy", count: 1)
        order.update!(completed_at: Time.current)
        delete "/v1/kingdoms/#{@kingdom.id}/train/#{order.id}", headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "training_order_already_resolved", response.parsed_body.dig("error", "code")
      end

      test "POST 404 for non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        post "/v1/kingdoms/#{@kingdom.id}/train",
          params: { building: "barracks", unit: "levy", count: 1 },
          headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
