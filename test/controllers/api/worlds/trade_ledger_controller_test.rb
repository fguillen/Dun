require "test_helper"

module Api
  module Worlds
    class TradeLedgerControllerTest < ActionDispatch::IntegrationTest
      setup do
        @admin  = create(:admin)
        @server = create(:server, owner: @admin)
        @world  = create(:world, :active, server: @server)
        @other_world = create(:world, :active, server: @server)

        @viewer = create(:player, email: "viewer@example.com")
        ServerMembership.create!(server: @server, player: @viewer)
        ServerAccess.create!(server: @server, kind: "invite", value: @viewer.email)
        create(:player_profile, server: @server, player: @viewer)

        sender_profile   = create(:player_profile, server: @server, handle: "Alice")
        receiver_profile = create(:player_profile, server: @server, handle: "Bob")
        @sender   = create(:kingdom, world: @world, player_profile: sender_profile)
        @receiver = create(:kingdom, world: @world, player_profile: receiver_profile)

        @c1 = create(:caravan, world: @world, sender_kingdom: @sender, receiver_kingdom: @receiver)
        @c2 = create(:caravan, world: @other_world)

        # Three entries in @world, one in @other_world.
        @e_old_alice = create(:trade_ledger_entry, caravan: @c1, world: @world,
          sender_handle_at_send: "Alice", receiver_handle_at_send: "Bob",
          resource: "gold", amount: 100, status: "delivered",
          recorded_at: 3.days.ago)
        @e_new_carol = create(:trade_ledger_entry, caravan: @c1, world: @world,
          sender_handle_at_send: "Carol", receiver_handle_at_send: "Dave",
          resource: "wood", amount: 50, status: "in_transit",
          recorded_at: 30.minutes.ago)
        @e_intercept = create(:trade_ledger_entry, caravan: @c1, world: @world,
          sender_handle_at_send: "Frank", receiver_handle_at_send: "Grace",
          attacker_handle: "Alice", resource: "stone", amount: 25, status: "intercepted",
          recorded_at: 5.minutes.ago)
        @e_other_world = create(:trade_ledger_entry, caravan: @c2, world: @other_world,
          sender_handle_at_send: "X", receiver_handle_at_send: "Y", resource: "iron", amount: 1,
          status: "delivered", recorded_at: Time.current)

        authenticate_as_player(@viewer)
      end

      test "GET returns ledger entries newest first, scoped to the world" do
        get "/v1/worlds/#{@world.id}/trade-ledger", headers: auth_headers

        assert_response :success
        body = response.parsed_body
        ids = body["entries"].map { |e| e["id"] }
        assert_equal [ @e_intercept.id, @e_new_carol.id, @e_old_alice.id ], ids
        assert_equal 3, body["pagy"]["count"]
        refute ids.include?(@e_other_world.id)
      end

      test "player filter matches sender, receiver, and attacker handles" do
        get "/v1/worlds/#{@world.id}/trade-ledger?player=Alice", headers: auth_headers
        body = response.parsed_body
        ids = body["entries"].map { |e| e["id"] }
        assert_includes ids, @e_old_alice.id   # sender
        assert_includes ids, @e_intercept.id   # attacker
        refute_includes ids, @e_new_carol.id   # unrelated
      end

      test "since filter narrows by recorded_at" do
        get "/v1/worlds/#{@world.id}/trade-ledger?since=2h", headers: auth_headers
        body = response.parsed_body
        ids = body["entries"].map { |e| e["id"] }
        assert_includes ids, @e_intercept.id
        assert_includes ids, @e_new_carol.id
        refute_includes ids, @e_old_alice.id  # 3 days old
      end

      test "pagination respects limit param" do
        get "/v1/worlds/#{@world.id}/trade-ledger?limit=2", headers: auth_headers
        body = response.parsed_body
        assert_equal 2, body["entries"].size
        assert_equal 3, body["pagy"]["count"]
        assert_equal 2, body["pagy"]["pages"]
      end

      test "404 when caller is not a member of the server" do
        stranger = create(:player, email: "stranger@example.com")
        authenticate_as_player(stranger)
        get "/v1/worlds/#{@world.id}/trade-ledger", headers: auth_headers
        assert_response :not_found
      end

      test "404 for unknown world" do
        get "/v1/worlds/01ZZZZZZZZZZZZZZZZZZZZZZZZ/trade-ledger", headers: auth_headers
        assert_response :not_found
      end
    end
  end
end
