require "test_helper"

module Api
  module Kingdoms
    class EventsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create(:admin)
        @server = create(:server, owner: @admin)
        @player = create(:player, email: "alice@example.com")
        ServerMembership.create!(server: @server, player: @player)
        ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
        @profile = create(:player_profile, server: @server, player: @player)

        @world = create(:world, :active, server: @server)
        @region = create(:region, world: @world)
        @kingdom = create(:kingdom, world: @world, player_profile: @profile, home_region: @region)

        authenticate_as_player(@player)
      end

      test "GET returns the event feed oldest-first with the expected shape" do
        building = create(:building, kingdom: @kingdom, kind: "quarry", level: 1)
        create(:build_order, kingdom: @kingdom, building: building, target_level: 2, completed_at: 2.hours.ago)
        create(:build_order, kingdom: @kingdom, building: building, target_level: 3, completed_at: 1.hour.ago)

        get "/v1/kingdoms/#{@kingdom.id}/events", headers: auth_headers
        assert_response :success

        events = response.parsed_body["events"]
        assert_equal 2, events.size
        assert events[0]["occurred_at"] <= events[1]["occurred_at"]
        assert_equal %w[occurred_at type description], events.first.keys
        assert_equal "build", events.first["type"]
      end

      test "GET respects the limit param" do
        building = create(:building, kingdom: @kingdom, kind: "quarry", level: 1)
        3.times { |i| create(:build_order, kingdom: @kingdom, building: building, target_level: i + 2, completed_at: (3 - i).hours.ago) }

        get "/v1/kingdoms/#{@kingdom.id}/events?limit=2", headers: auth_headers
        assert_response :success
        assert_equal 2, response.parsed_body["events"].size
      end

      test "GET returns an empty list when nothing has happened" do
        get "/v1/kingdoms/#{@kingdom.id}/events", headers: auth_headers
        assert_response :success
        assert_equal [], response.parsed_body["events"]
      end

      test "GET 404 for a player who does not own the kingdom" do
        stranger = create(:player)
        authenticate_as_player(stranger)
        get "/v1/kingdoms/#{@kingdom.id}/events", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
