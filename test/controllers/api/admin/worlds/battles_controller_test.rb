require "test_helper"

module Api
  module Admin
    module Worlds
      class BattlesControllerTest < ActionDispatch::IntegrationTest
        setup do
          @admin = create(:admin)
          @server = create(:server, owner: @admin)
          @world = create(:world, :active, server: @server)
          region = create(:region, world: @world)
          @attacker = create(:kingdom, world: @world)
          @defender = create(:kingdom, world: @world)

          @battle_1 = create(:battle, world: @world, region: region,
            attacker_kingdom: @attacker, defender_kingdom: @defender,
            ended_at: 1.day.ago)
          @battle_2 = create(:battle, world: @world, region: region,
            attacker_kingdom: @attacker, defender_kingdom: @defender,
            ended_at: 1.hour.ago)
          # Battle in a different world for the same admin
          other_world = create(:world, :active, server: @server)
          other_region = create(:region, world: other_world)
          create(:battle, world: other_world, region: other_region)
        end

        test "GET requires admin auth" do
          get "/v1/admin/worlds/#{@world.id}/battles"
          assert_response :unauthorized
        end

        test "GET lists all battles in the administered world, newest first" do
          authenticate_as_admin(@admin)
          get "/v1/admin/worlds/#{@world.id}/battles", headers: auth_headers
          assert_response :success
          ids = response.parsed_body["battles"].map { |b| b["id"] }
          assert_equal [ @battle_2.id, @battle_1.id ], ids
          assert_equal 2, response.parsed_body["total_count"]
        end

        test "GET 404 when admin does not administer the world's server" do
          stranger = create(:admin)
          authenticate_as_admin(stranger)
          get "/v1/admin/worlds/#{@world.id}/battles", headers: auth_headers
          assert_response :not_found
        end

        test "GET rejects player-scope ApiKey" do
          player = create(:player)
          authenticate_as_player(player)
          get "/v1/admin/worlds/#{@world.id}/battles", headers: auth_headers
          assert_response :unauthorized
        end
      end
    end
  end
end
