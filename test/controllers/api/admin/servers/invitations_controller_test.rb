require "test_helper"

module Api
  module Admin
    module Servers
      class InvitationsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @admin  = create(:admin)
          @server = create(:server, owner: @admin)
          authenticate_as_admin(@admin)
        end

        test "POST creates an invite-kind ServerAccess" do
          post "/v1/admin/servers/#{@server.id}/invitations",
               params: { email: "Guest@Example.com" }, headers: auth_headers, as: :json

          assert_response :created
          assert_equal "guest@example.com", response.parsed_body["email"]
          assert ServerAccess.exists?(server: @server, kind: "invite", value: "guest@example.com")
        end

        test "GET lists invitations" do
          ServerInvitations::Create.call(server: @server, email: "a@example.com")
          ServerInvitations::Create.call(server: @server, email: "b@example.com")

          get "/v1/admin/servers/#{@server.id}/invitations", headers: auth_headers
          assert_response :success

          emails = response.parsed_body["invitations"].map { |i| i["email"] }
          assert_equal %w[a@example.com b@example.com], emails
        end

        test "DELETE removes the invitation" do
          access = ServerInvitations::Create.call(server: @server, email: "leaving@example.com")

          delete "/v1/admin/servers/#{@server.id}/invitations/#{access.id}", headers: auth_headers
          assert_response :no_content
          assert_not ServerAccess.exists?(access.id)
        end
      end
    end
  end
end
