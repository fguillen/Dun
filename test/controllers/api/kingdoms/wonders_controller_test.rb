require "test_helper"

module Api
  module Kingdoms
    class WondersControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @world = create(:world, :active, server: @server)
        @region = create(:region, world: @world)

        @player = create(:player, email: "alice@example.com")
        ServerMembership.create!(server: @server, player: @player)
        ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
        @profile = create(:player_profile, server: @server, player: @player, handle: "Alice")

        @kingdom = create(:kingdom, :with_buildings,
          world: @world, player_profile: @profile, home_region: @region)
        @kingdom.buildings.find_by(kind: "warehouse").update!(level: 17)
        @kingdom.update!(stockpiles: {
          "gold" => 300_000, "wood" => 300_000, "stone" => 700_000, "iron" => 300_000,
          "checkpoint_at" => Time.current.iso8601
        })
        %w[town_hall quarry].each { |k| @kingdom.buildings.find_by(kind: k).update!(level: 10) }
        @kingdom.buildings.find_by(kind: "barracks").update!(level: 5)
        @kingdom.buildings.find_by(kind: "iron_mine").update!(level: 5)
        @kingdom.buildings.find_by(kind: "siege_workshop").update!(level: 5)
        3.times { |i| create(:node, region: create(:region, world: @world, name: "n-#{i}"), owner_kingdom_id: @kingdom.id) }

        authenticate_as_player(@player)
      end

      test "GET /v1/kingdoms/:id/wonder returns nil when none exists" do
        get "/v1/kingdoms/#{@kingdom.id}/wonder", headers: auth_headers
        assert_response :success
        assert_nil response.parsed_body["wonder"]
      end

      test "POST creates a Wonder, returns 201 with serialized body" do
        post "/v1/kingdoms/#{@kingdom.id}/wonder",
          params: { name: "sky_tower" },
          headers: auth_headers,
          as: :json

        assert_response :created
        body = response.parsed_body
        assert_equal "construction", body["status"]
        assert_equal "sky_tower", body["name"]
        assert_equal 1_000, body["hp"]
        assert_equal 10_000, body["target_hp"]
      end

      test "POST 422 when name is unknown" do
        post "/v1/kingdoms/#{@kingdom.id}/wonder",
          params: { name: "atlantis" },
          headers: auth_headers,
          as: :json
        assert_response :unprocessable_entity
        assert_equal "unknown_wonder_name", response.parsed_body["error"]["code"]
      end

      test "POST 422 when prereqs are unmet" do
        @kingdom.buildings.find_by(kind: "quarry").update!(level: 5)
        post "/v1/kingdoms/#{@kingdom.id}/wonder",
          params: { name: "sky_tower" },
          headers: auth_headers,
          as: :json
        assert_response :unprocessable_entity
        assert_equal "wonder_prereq_unmet", response.parsed_body["error"]["code"]
      end

      test "GET returns the existing Wonder (after auto-applying construction)" do
        wonder = create(:wonder, kingdom: @kingdom, status: "construction", hp: 1_000,
          last_construction_at: 5.hours.ago)
        get "/v1/kingdoms/#{@kingdom.id}/wonder", headers: auth_headers
        assert_response :success
        body = response.parsed_body
        assert_equal wonder.id, body["id"]
        assert_operator body["hp"], :>, 1_000
      end

      test "POST /wonder/milestone deducts cost and clears pending" do
        wonder = create(:wonder, kingdom: @kingdom, status: "construction",
          hp: 2_500, pending_milestone_percent: 25)

        post "/v1/kingdoms/#{@kingdom.id}/wonder/milestone",
          params: { percent: 25 },
          headers: auth_headers,
          as: :json
        assert_response :success
        assert_nil response.parsed_body["pending_milestone_percent"]
        assert_equal true, response.parsed_body["milestones_paid"]["25"]
      end

      test "POST /wonder/milestone 422 when no milestone pending" do
        create(:wonder, kingdom: @kingdom, status: "construction", hp: 1_500)

        post "/v1/kingdoms/#{@kingdom.id}/wonder/milestone",
          params: { percent: 25 },
          headers: auth_headers,
          as: :json
        assert_response :unprocessable_entity
        assert_equal "no_milestone_pending", response.parsed_body["error"]["code"]
      end

      test "POST /wonder/repair spends Stone and bumps hp" do
        wonder = create(:wonder, kingdom: @kingdom, status: "construction", hp: 5_000)

        post "/v1/kingdoms/#{@kingdom.id}/wonder/repair",
          params: { hp: 100 },
          headers: auth_headers,
          as: :json
        assert_response :success
        assert_equal 5_100, response.parsed_body["hp"]
      end

      test "DELETE cancels a live Wonder (destroys it)" do
        wonder = create(:wonder, kingdom: @kingdom, status: "construction")
        delete "/v1/kingdoms/#{@kingdom.id}/wonder", headers: auth_headers
        assert_response :success
        assert_equal "destroyed", response.parsed_body["status"]
      end

      test "non-owner cannot access another player's Wonder" do
        stranger = create(:player, email: "stranger@example.com")
        ServerMembership.create!(server: @server, player: stranger)
        create(:player_profile, server: @server, player: stranger)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/wonder", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
