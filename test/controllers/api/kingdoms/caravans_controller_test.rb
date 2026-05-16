require "test_helper"

module Api
  module Kingdoms
    class CaravansControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin  = create(:admin)
        @server = create(:server, owner: @admin)
        @world  = create(:world, :active, server: @server)

        @origin = create(:region, world: @world, terrain: "plains", name: "OriginHome")
        @dest   = create(:region, world: @world, terrain: "plains", name: "DestHome")
        RegionAdjacency.connect(@origin, @dest)

        @sender_player = create(:player, email: "alice@example.com")
        ServerMembership.create!(server: @server, player: @sender_player)
        ServerAccess.create!(server: @server, kind: "invite", value: @sender_player.email)
        @sender_profile = create(:player_profile, server: @server, player: @sender_player, handle: "Alice")

        @receiver_player = create(:player, email: "bob@example.com")
        ServerMembership.create!(server: @server, player: @receiver_player)
        @receiver_profile = create(:player_profile, server: @server, player: @receiver_player, handle: "Bob")

        @sender = create(:kingdom, :with_buildings,
          world: @world, player_profile: @sender_profile, home_region: @origin)
        @sender.update!(stockpiles: { "gold" => 1_000, "wood" => 0, "stone" => 0, "iron" => 0,
                                      "checkpoint_at" => Time.current.iso8601 })
        @receiver = create(:kingdom, :with_buildings,
          world: @world, player_profile: @receiver_profile, home_region: @dest)

        @source_army = create(:army, kingdom: @sender, location_region: @origin,
          name: "Home Guard", composition: { "knight" => 10 })

        authenticate_as_player(@sender_player)
      end

      test "POST creates a caravan and returns its serialized form" do
        post "/v1/kingdoms/#{@sender.id}/caravans",
          params: {
            receiver_handle: "Bob",
            source_army_id: @source_army.id,
            payload: { gold: 200 },
            escort_units: { knight: 5 }
          },
          headers: auth_headers,
          as: :json

        assert_response :created
        body = response.parsed_body
        assert_equal "in_transit", body["status"]
        assert_equal @sender.id, body["sender_kingdom_id"]
        assert_equal @receiver.id, body["receiver_kingdom_id"]
        assert_equal({ "gold" => 200 }, body["payload"])
        assert_equal({ "knight" => 5 }, body["escort_units"])
      end

      test "POST 422 when receiver handle is unknown" do
        post "/v1/kingdoms/#{@sender.id}/caravans",
          params: {
            receiver_handle: "Nobody",
            source_army_id: @source_army.id,
            payload: { gold: 100 }, escort_units: { knight: 2 }
          },
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity
        assert_equal "receiver_not_found", response.parsed_body.dig("error", "code")
      end

      test "POST 422 when payload exceeds escort capacity" do
        post "/v1/kingdoms/#{@sender.id}/caravans",
          params: {
            receiver_handle: "Bob",
            source_army_id: @source_army.id,
            payload: { gold: 10_000 },
            escort_units: { knight: 1 }
          },
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity
        assert_equal "insufficient_capacity", response.parsed_body.dig("error", "code")
      end

      test "POST 422 when sender lacks stockpile" do
        @sender.update!(stockpiles: { "gold" => 5, "wood" => 0, "stone" => 0, "iron" => 0,
                                      "checkpoint_at" => Time.current.iso8601 })

        post "/v1/kingdoms/#{@sender.id}/caravans",
          params: {
            receiver_handle: "Bob",
            source_army_id: @source_army.id,
            payload: { gold: 100 },
            escort_units: { knight: 2 }
          },
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity
        assert_equal "insufficient_resources", response.parsed_body.dig("error", "code")
      end

      test "POST 422 on self-trade" do
        post "/v1/kingdoms/#{@sender.id}/caravans",
          params: {
            receiver_handle: "Alice",
            source_army_id: @source_army.id,
            payload: { gold: 100 }, escort_units: { knight: 2 }
          },
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity
        assert_equal "self_trade", response.parsed_body.dig("error", "code")
      end

      test "POST 404 when caller does not own the kingdom" do
        stranger = create(:player, email: "stranger@example.com")
        authenticate_as_player(stranger)

        post "/v1/kingdoms/#{@sender.id}/caravans",
          params: { receiver_handle: "Bob", source_army_id: @source_army.id,
                    payload: { gold: 100 }, escort_units: { knight: 2 } },
          headers: auth_headers,
          as: :json

        assert_response :not_found
      end

      test "POST 404 when source_army belongs to a different kingdom" do
        other_profile = create(:player_profile, server: @server)
        other = create(:kingdom, :with_buildings, world: @world, player_profile: other_profile,
          home_region: create(:region, world: @world))
        other_army = create(:army, kingdom: other, composition: { "knight" => 5 })

        post "/v1/kingdoms/#{@sender.id}/caravans",
          params: { receiver_handle: "Bob", source_army_id: other_army.id,
                    payload: { gold: 100 }, escort_units: { knight: 2 } },
          headers: auth_headers,
          as: :json

        assert_response :not_found
      end
    end
  end
end
