require "test_helper"

module Api
  module Kingdoms
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
          kingdom: @kingdom, location_region: region, composition: { "levy" => 7 })

        authenticate_as_player(@player)
      end

      test "GET lists this kingdom's armies" do
        create(:army, kingdom: @kingdom, location_region: @kingdom.home_region, name: "Vanguard")
        get "/v1/kingdoms/#{@kingdom.id}/armies", headers: auth_headers
        assert_response :success
        names = response.parsed_body["armies"].map { |a| a["name"] }
        assert_includes names, Army::GARRISON_NAME
        assert_includes names, "Vanguard"
      end

      test "GET 404 for non-owner" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/armies", headers: auth_headers
        assert_response :not_found
      end

      test "GET list embeds each army's active_march" do
        target = create(:region, world: @kingdom.world, name: "Front")
        marcher = create(:army, :marching,
          kingdom: @kingdom, location_region: @kingdom.home_region, name: "Vanguard")
        order = create(:march_order, army: marcher,
          origin_region: @kingdom.home_region, target_region: target,
          intent: "reinforce", arrives_at: 1.hour.from_now)

        get "/v1/kingdoms/#{@kingdom.id}/armies", headers: auth_headers
        assert_response :success
        armies = response.parsed_body["armies"]

        garrison = armies.find { |a| a["name"] == Army::GARRISON_NAME }
        assert_nil garrison["active_march"]

        vanguard = armies.find { |a| a["name"] == "Vanguard" }
        assert_equal order.id, vanguard.dig("active_march", "march_order_id")
        assert_equal "reinforce", vanguard.dig("active_march", "intent")
        assert_equal target.id, vanguard.dig("active_march", "target_region_id")
        assert_not_nil vanguard.dig("active_march", "arrives_at")
      end
    end
  end
end
