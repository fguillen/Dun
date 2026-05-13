require "test_helper"

module Api
  module Admin
    module Worlds
      class InvitationsControllerTest < ActionDispatch::IntegrationTest
        test "GET /v1/admin/worlds/:world_id/invitations requires admin auth" do
          world = create(:world)
          get "/v1/admin/worlds/#{world.id}/invitations"
          assert_response :unauthorized
        end

        test "GET lists invitations on the administered world" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          world = create(:world, server: server)
          a = create(:world_invitation, world: world, email: "a@x.com")
          b = create(:world_invitation, world: world, email: "b@x.com")
          _other = create(:world_invitation)
          authenticate_as_admin(admin)

          get "/v1/admin/worlds/#{world.id}/invitations", headers: auth_headers
          assert_response :success
          emails = response.parsed_body["invitations"].map { |i| i["email"] }
          assert_equal [ a.email, b.email ].sort, emails
        end

        test "GET returns 404 for a non-administering admin" do
          admin = create(:admin)
          other_world = create(:world)
          authenticate_as_admin(admin)

          get "/v1/admin/worlds/#{other_world.id}/invitations", headers: auth_headers
          assert_response :not_found
        end

        test "POST creates an invitation and normalizes the email" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          world = create(:world, server: server)
          authenticate_as_admin(admin)

          post "/v1/admin/worlds/#{world.id}/invitations",
               params: { email: "Alice@Example.COM" },
               headers: auth_headers, as: :json
          assert_response :created
          assert_equal "alice@example.com", response.parsed_body["email"]
          assert_equal admin.id, response.parsed_body["invited_by_admin_id"]
        end

        test "POST is idempotent on duplicates" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          world = create(:world, server: server)
          authenticate_as_admin(admin)

          2.times do
            post "/v1/admin/worlds/#{world.id}/invitations",
                 params: { email: "x@y.com" },
                 headers: auth_headers, as: :json
            assert_response :created
          end

          assert_equal 1, world.world_invitations.count
        end

        test "DELETE removes an invitation" do
          admin = create(:admin)
          server = create(:server, owner: admin)
          world = create(:world, server: server)
          inv = create(:world_invitation, world: world)
          authenticate_as_admin(admin)

          delete "/v1/admin/worlds/#{world.id}/invitations/#{inv.id}", headers: auth_headers
          assert_response :no_content
          assert_not WorldInvitation.exists?(inv.id)
        end

        test "POST rejects a player-scope ApiKey" do
          player = create(:player)
          world = create(:world)
          authenticate_as_player(player)

          post "/v1/admin/worlds/#{world.id}/invitations",
               params: { email: "a@b.com" },
               headers: auth_headers, as: :json
          assert_response :unauthorized
        end
      end
    end
  end
end
