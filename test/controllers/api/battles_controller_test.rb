require "test_helper"

module Api
  class BattlesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create(:admin)
      @server = create(:server, owner: @admin)
      @player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: @server, player: @player)
      ServerAccess.create!(server: @server, kind: "invite", value: @player.email)
      profile = create(:player_profile, server: @server, player: @player)

      @world = create(:world, :grace, server: @server)
      region = create(:region, world: @world)
      @kingdom = create(:kingdom, world: @world, player_profile: profile, home_region: region)
      @other_kingdom = create(:kingdom, world: @world)

      @battle = create(:battle, world: @world, region: region,
        attacker_kingdom: @kingdom, defender_kingdom: @other_kingdom,
        log: [ { "round" => 1, "attacker_damage_dealt" => 500 } ])
      create(:battle_participant, battle: @battle, kingdom: @kingdom, side: "attacker")
      create(:battle_participant, battle: @battle, kingdom: @other_kingdom, side: "defender")

      authenticate_as_player(@player)
    end

    test "GET returns the battle with participants" do
      get "/v1/battles/#{@battle.id}", headers: auth_headers
      assert_response :success
      body = response.parsed_body
      assert_equal @battle.id, body["battle"]["id"]
      assert_equal 2, body["participants"].size
      sides = body["participants"].map { |p| p["side"] }.sort
      assert_equal %w[attacker defender], sides
      assert_equal 1, body["battle"]["log"].size
    end

    test "GET returns 404 when the player owns neither side" do
      stranger = create(:player)
      authenticate_as_player(stranger)
      get "/v1/battles/#{@battle.id}", headers: auth_headers
      assert_response :not_found
    end

    test "GET returns 404 when the battle does not exist" do
      get "/v1/battles/missing-id", headers: auth_headers
      assert_response :not_found
    end

    test "GET requires player auth" do
      get "/v1/battles/#{@battle.id}"
      assert_response :unauthorized
    end
  end
end
