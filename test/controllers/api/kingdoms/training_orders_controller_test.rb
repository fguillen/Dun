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

      test "GET preview returns per-unit and total cost, total time, max_affordable_count" do
        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "barracks", unit: "levy", count: 5 },
          headers: auth_headers
        assert_response :success
        body = response.parsed_body
        per_unit = ::Units::Catalog.cost_for("levy")
        assert_equal per_unit, body["per_unit_cost"]
        assert_equal per_unit.transform_values { |v| v * 5 }, body["total_cost"]
        assert_equal "barracks", body["building_kind"]
        assert_equal "levy", body["unit"]
        assert_equal 5, body["count"]
        assert_equal true, body["building_built"]
        assert_equal true, body["unit_trainable_here"]
        assert_equal true, body["affordable"]
        assert body["max_affordable_count"] >= 5
        assert body["per_unit_seconds"] > 0
        assert_equal body["per_unit_seconds"] * 5, body["total_seconds"]
      end

      test "GET preview surfaces shortfall via missing and affordable=false" do
        @kingdom.update!(stockpiles: {
          "gold" => 10, "wood" => 10, "stone" => 10, "iron" => 10,
          "checkpoint_at" => Time.current.iso8601
        })
        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "barracks", unit: "pikeman", count: 1 },
          headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal false, body["affordable"]
        assert body["missing"]["iron"] > 0
      end

      test "GET preview returns unit_trainable_here=false for unit/building mismatch (informational)" do
        @kingdom.buildings.find_by(kind: "stable").update!(level: 1)
        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "stable", unit: "levy", count: 1 },
          headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal false, body["unit_trainable_here"]
      end

      test "GET preview returns 422 for unknown unit" do
        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "barracks", unit: "ninja", count: 1 },
          headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "unknown_unit", response.parsed_body.dig("error", "code")
      end

      test "GET preview returns 422 for invalid building kind" do
        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "warehouse", unit: "levy", count: 1 },
          headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "invalid_building_kind", response.parsed_body.dig("error", "code")
      end

      test "GET preview returns 422 for non-positive count" do
        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "barracks", unit: "levy", count: 0 },
          headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "invalid_count", response.parsed_body.dig("error", "code")
      end

      test "GET preview returns 404 for non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "barracks", unit: "levy", count: 1 },
          headers: auth_headers
        assert_response :not_found
      end

      test "GET catalog without building returns all three military buildings" do
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal @kingdom.id.to_s, body["kingdom_id"]
        assert_equal %w[barracks stable siege_workshop],
          body["buildings"].map { |b| b["building_kind"] }
      end

      test "GET catalog with building filter returns only that building" do
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog",
          params: { building: "barracks" }, headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["buildings"].length
        building = body["buildings"].first
        assert_equal "barracks", building["building_kind"]
        assert_equal %w[levy archer pikeman], building["units"].map { |u| u["unit"] }
      end

      test "GET catalog unit entry matches train/preview at count 1" do
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog",
          params: { building: "barracks" }, headers: auth_headers
        catalog_unit = response.parsed_body["buildings"].first["units"]
          .find { |u| u["unit"] == "levy" }

        get "/v1/kingdoms/#{@kingdom.id}/train/preview",
          params: { building: "barracks", unit: "levy", count: 1 },
          headers: auth_headers
        preview = response.parsed_body

        assert_equal preview["per_unit_cost"], catalog_unit["per_unit_cost"]
        assert_equal preview["per_unit_seconds"], catalog_unit["per_unit_seconds"]
        assert_equal preview["max_affordable_count"], catalog_unit["max_affordable_count"]
      end

      test "GET catalog marks units trainable for a built building" do
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog",
          params: { building: "barracks" }, headers: auth_headers
        building = response.parsed_body["buildings"].first
        assert_equal true, building["building_built"]
        assert building["units"].all? { |u| u["trainable"] }
      end

      test "GET catalog marks units not trainable for an unbuilt building" do
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog",
          params: { building: "siege_workshop" }, headers: auth_headers
        building = response.parsed_body["buildings"].first
        assert_equal false, building["building_built"]
        assert building["units"].none? { |u| u["trainable"] }
      end

      test "GET catalog returns 422 for invalid building kind" do
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog",
          params: { building: "warehouse" }, headers: auth_headers
        assert_response :unprocessable_entity
        assert_equal "invalid_building_kind", response.parsed_body.dig("error", "code")
      end

      test "GET catalog returns 404 for non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog", headers: auth_headers
        assert_response :not_found
      end

      test "GET catalog returns 404 for unknown kingdom" do
        get "/v1/kingdoms/does-not-exist/train/catalog", headers: auth_headers
        assert_response :not_found
      end

      test "GET catalog returns 401 without auth" do
        get "/v1/kingdoms/#{@kingdom.id}/train/catalog"
        assert_response :unauthorized
      end
    end
  end
end
