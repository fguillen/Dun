require "test_helper"

module Api
  module Kingdoms
    class BuildingsControllerTest < ActionDispatch::IntegrationTest
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
          "gold" => 50_000, "wood" => 50_000, "stone" => 50_000, "iron" => 50_000,
          "checkpoint_at" => Time.current.iso8601
        })
        authenticate_as_player(@player)
      end

      test "GET index returns 401 without auth" do
        get "/v1/kingdoms/#{@kingdom.id}/buildings"
        assert_response :unauthorized
      end

      test "GET index returns 404 for non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/buildings", headers: auth_headers
        assert_response :not_found
      end

      test "GET index returns one row per Buildings::Catalog::KINDS, sorted by kind" do
        get "/v1/kingdoms/#{@kingdom.id}/buildings", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal ::Buildings::Catalog::KINDS.length, body["buildings"].length
        kinds = body["buildings"].map { |row| row["kind"] }
        assert_equal ::Buildings::Catalog::KINDS.sort, kinds
      end

      test "GET index includes top-level kingdom_id matching the path param" do
        get "/v1/kingdoms/#{@kingdom.id}/buildings", headers: auth_headers
        assert_response :success
        assert_equal @kingdom.id, response.parsed_body["kingdom_id"]
      end

      test "GET index row exposes id, current_level, target_level, cost, affordable, upgrade_possible, build_order" do
        get "/v1/kingdoms/#{@kingdom.id}/buildings", headers: auth_headers
        assert_response :success
        row = response.parsed_body["buildings"].find { |r| r["kind"] == "quarry" }
        assert_equal @kingdom.buildings.find_by(kind: "quarry").id, row["id"]
        assert_equal 1, row["current_level"]
        assert_equal 2, row["target_level"]
        assert_equal false, row["at_max_level"]
        assert_equal ::Buildings::CostFor.call(kind: "quarry", level: 2), row["cost"]
        assert_equal true, row["affordable"]
        assert_equal true, row["upgrade_possible"]
        assert_nil row["build_order"]
      end

      test "GET index surfaces in-progress build order under build_order" do
        order = ::Buildings::Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
        get "/v1/kingdoms/#{@kingdom.id}/buildings", headers: auth_headers
        assert_response :success
        rows = response.parsed_body["buildings"]
        barracks_row = rows.find { |r| r["kind"] == "barracks" }
        other_row    = rows.find { |r| r["kind"] == "quarry" }
        assert_equal order.id, barracks_row["build_order"]["id"]
        assert_equal "barracks", barracks_row["build_order"]["kind"]
        assert_nil other_row["build_order"]
      end

      test "GET index forces upgrade_possible to false when an in-progress order exists" do
        ::Buildings::Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)
        get "/v1/kingdoms/#{@kingdom.id}/buildings", headers: auth_headers
        row = response.parsed_body["buildings"].find { |r| r["kind"] == "barracks" }
        assert_equal false, row["upgrade_possible"]
        assert_not_nil row["build_order"]
      end

      test "GET index with upgrade_possible=true narrows to actionable rows" do
        @kingdom.buildings.find_by(kind: "walls").update!(level: ::Buildings::Catalog::MAX_LEVEL)
        ::Buildings::Queue.call(kingdom: @kingdom, kind: "barracks", target_level: 2)

        get "/v1/kingdoms/#{@kingdom.id}/buildings",
          params: { upgrade_possible: "true" }, headers: auth_headers
        assert_response :success

        rows = response.parsed_body["buildings"]
        kinds = rows.map { |r| r["kind"] }
        rows.each do |r|
          assert_equal true, r["upgrade_possible"], "#{r['kind']} should be upgradable"
        end
        refute_includes kinds, "walls"
        refute_includes kinds, "barracks"
        refute_includes kinds, "siege_workshop"
        assert_includes kinds, "quarry"
      end

      test "GET index with upgrade_possible=false returns the full list" do
        get "/v1/kingdoms/#{@kingdom.id}/buildings",
          params: { upgrade_possible: "false" }, headers: auth_headers
        assert_response :success
        assert_equal ::Buildings::Catalog::KINDS.length, response.parsed_body["buildings"].length
      end

      test "GET index resolves ripe build orders before computing the list" do
        order = ::Buildings::Queue.call(kingdom: @kingdom, kind: "quarry", target_level: 2)
        order.update_columns(completes_at: 1.minute.ago)

        get "/v1/kingdoms/#{@kingdom.id}/buildings", headers: auth_headers
        assert_response :success

        row = response.parsed_body["buildings"].find { |r| r["kind"] == "quarry" }
        assert_equal 2, row["current_level"]
        assert_nil row["build_order"]
      end
    end
  end
end
