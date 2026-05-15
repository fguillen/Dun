require "test_helper"

module Api
  module Kingdoms
    class BattlesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @player = create(:player, email: "alice@example.com")
        ServerMembership.create!(server: @server, player: @player)
        ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
        profile = create(:player_profile, server: @server, player: @player)

        @world = create(:world, :grace, server: @server)
        @region = create(:region, world: @world)
        @kingdom = create(:kingdom, world: @world, player_profile: profile, home_region: @region)
        @other_kingdom = create(:kingdom, world: @world)

        authenticate_as_player(@player)
      end

      test "GET lists battles where the kingdom is attacker, newest first" do
        old = create(:battle, world: @world, region: @region,
          attacker_kingdom: @kingdom, defender_kingdom: @other_kingdom,
          ended_at: 2.days.ago)
        recent = create(:battle, world: @world, region: @region,
          attacker_kingdom: @kingdom, defender_kingdom: @other_kingdom,
          ended_at: 1.hour.ago)

        get "/v1/kingdoms/#{@kingdom.id}/battles", headers: auth_headers
        assert_response :success
        ids = response.parsed_body["battles"].map { |b| b["id"] }
        assert_equal [ recent.id, old.id ], ids
        assert_equal 2, response.parsed_body["total_count"]
      end

      test "GET includes battles where the kingdom is defender" do
        attacking = create(:battle, world: @world, region: @region,
          attacker_kingdom: @other_kingdom, defender_kingdom: @kingdom,
          ended_at: 1.hour.ago)
        get "/v1/kingdoms/#{@kingdom.id}/battles", headers: auth_headers
        assert_response :success
        ids = response.parsed_body["battles"].map { |b| b["id"] }
        assert_includes ids, attacking.id
      end

      test "GET excludes battles for other kingdoms" do
        other_kingdom_2 = create(:kingdom, world: @world)
        create(:battle, world: @world, region: @region,
          attacker_kingdom: other_kingdom_2, defender_kingdom: @other_kingdom,
          ended_at: 1.hour.ago)
        get "/v1/kingdoms/#{@kingdom.id}/battles", headers: auth_headers
        assert_response :success
        assert_equal 0, response.parsed_body["total_count"]
      end

      test "GET respects limit and offset" do
        3.times do |i|
          create(:battle, world: @world, region: @region,
            attacker_kingdom: @kingdom, defender_kingdom: @other_kingdom,
            ended_at: (10 - i).hours.ago)
        end
        get "/v1/kingdoms/#{@kingdom.id}/battles?limit=2", headers: auth_headers
        assert_response :success
        assert_equal 2, response.parsed_body["battles"].size
        assert_equal 3, response.parsed_body["total_count"]

        get "/v1/kingdoms/#{@kingdom.id}/battles?limit=2&offset=2", headers: auth_headers
        assert_equal 1, response.parsed_body["battles"].size
      end

      test "GET 404 for a non-owner player" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/battles", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
