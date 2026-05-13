require "test_helper"

module Api
  module Admin
    module Servers
      class MembersControllerTest < ActionDispatch::IntegrationTest
        test "lists memberships with player names" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          alice = create(:player, email: "alice@example.com", name: "Alice")
          bob   = create(:player, email: "bob@example.com",   name: "Bob")
          ServerMembership.create!(server: server, player: alice)
          ServerMembership.create!(server: server, player: bob)
          authenticate_as_admin(admin)

          get "/v1/admin/servers/#{server.id}/members", headers: auth_headers
          assert_response :success

          names = response.parsed_body["members"].map { |m| m.dig("player", "name") }.sort
          assert_equal %w[Alice Bob], names
        end
      end
    end
  end
end
