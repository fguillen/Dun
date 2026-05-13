require "test_helper"

module Api
  module Admin
    module Servers
      class AdminsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @admin  = create(:admin)
          @server = create(:server, owner: @admin)
          authenticate_as_admin(@admin)
        end

        test "GET lists current adminships (starting with the owner)" do
          get "/v1/admin/servers/#{@server.id}/admins", headers: auth_headers
          assert_response :success
          emails = response.parsed_body["admins"].map { |a| a.dig("admin", "email") }
          assert_includes emails, @admin.email
        end

        test "POST invites a new admin" do
          post "/v1/admin/servers/#{@server.id}/admins",
               params: { email: "co-admin@example.com" }, headers: auth_headers, as: :json
          assert_response :created

          body = response.parsed_body
          assert_equal "co-admin@example.com", body.dig("admin", "email")
          assert_equal "admin", body["role"]
          assert_equal @admin.id, body["granted_by_admin_id"]
        end

        test "DELETE revokes a co-admin" do
          co_admin = create(:admin)
          ::Admins::Invite.call(by_admin: @admin, server: @server, email: co_admin.email)

          delete "/v1/admin/servers/#{@server.id}/admins/#{co_admin.id}", headers: auth_headers
          assert_response :no_content

          assert_not ::ServerAdminship.exists?(server: @server, admin: co_admin)
        end

        test "DELETE returns 422 when removing the last admin" do
          delete "/v1/admin/servers/#{@server.id}/admins/#{@admin.id}", headers: auth_headers

          assert_response :unprocessable_entity
          assert_equal "last_admin", response.parsed_body.dig("error", "code")
        end

        test "an admin cannot manage admins on a server they don't administer" do
          other_server = create(:server)
          get "/v1/admin/servers/#{other_server.id}/admins", headers: auth_headers
          assert_response :not_found
        end
      end
    end
  end
end
