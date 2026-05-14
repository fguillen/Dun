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
    end
  end
end
