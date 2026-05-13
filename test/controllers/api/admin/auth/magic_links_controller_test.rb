require "test_helper"

module Api
  module Admin
    module Auth
      class MagicLinksControllerTest < ActionDispatch::IntegrationTest
        include ActionMailer::TestHelper

        test "POST /v1/admin/auth/magic_link enqueues an admin-scope mailer" do
          assert_enqueued_emails 1 do
            post "/v1/admin/auth/magic_link", params: { email: "boss@example.com" }, as: :json
          end

          assert_response :accepted
          link = MagicLink.order(:id).last
          assert_equal "Admin", link.owner_type
        end

        test "POST /v1/admin/auth/exchange returns admin api_key" do
          _record, raw_token = MagicLink.generate_for(owner_type: "Admin", email: "boss@example.com")

          post "/v1/admin/auth/exchange", params: { token: raw_token }, as: :json

          assert_response :created
          body = response.parsed_body
          assert body["api_key"].present?
          assert_equal "admin", body.dig("owner", "type")
        end

        test "POST /v1/admin/auth/exchange rejects a player-scope token" do
          _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

          post "/v1/admin/auth/exchange", params: { token: raw_token }, as: :json
          assert_response :unauthorized
        end
      end
    end
  end
end
