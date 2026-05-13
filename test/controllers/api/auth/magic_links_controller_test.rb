require "test_helper"

module Api
  module Auth
    class MagicLinksControllerTest < ActionDispatch::IntegrationTest
      include ActionMailer::TestHelper

      test "POST /v1/auth/magic_link enqueues a player-scope mailer and returns 202" do
        assert_enqueued_emails 1 do
          post "/v1/auth/magic_link", params: { email: "alice@example.com" }, as: :json
        end

        assert_response :accepted
        link = MagicLink.order(:id).last
        assert_equal "Player", link.owner_type
        assert_equal "alice@example.com", link.email
      end

      test "POST /v1/auth/magic_link requires email" do
        post "/v1/auth/magic_link", params: {}, as: :json

        assert_response :unprocessable_entity
        assert_equal "param_missing", response.parsed_body.dig("error", "code")
      end

      test "POST /v1/auth/exchange returns api_key + expires_at on a valid token" do
        _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

        post "/v1/auth/exchange", params: { token: raw_token }, as: :json

        assert_response :created
        body = response.parsed_body
        assert body["api_key"].present?
        assert body["expires_at"].present?
        assert_equal "alice@example.com", body.dig("owner", "email")
        assert_equal "player", body.dig("owner", "type")
      end

      test "POST /v1/auth/exchange rejects a token of the wrong scope" do
        _record, raw_token = MagicLink.generate_for(owner_type: "Admin", email: "x@example.com")

        post "/v1/auth/exchange", params: { token: raw_token }, as: :json

        assert_response :unauthorized
        assert_equal "invalid_token", response.parsed_body.dig("error", "code")
      end

      test "POST /v1/auth/exchange rejects an expired token" do
        record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "x@example.com")
        record.update_columns(expires_at: 1.minute.ago)

        post "/v1/auth/exchange", params: { token: raw_token }, as: :json

        assert_response :unauthorized
        assert_equal "expired", response.parsed_body.dig("error", "code")
      end

      test "POST /v1/auth/exchange rejects a re-used token" do
        _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "x@example.com")
        post "/v1/auth/exchange", params: { token: raw_token }, as: :json
        assert_response :created

        post "/v1/auth/exchange", params: { token: raw_token }, as: :json
        assert_response :unauthorized
        assert_equal "already_consumed", response.parsed_body.dig("error", "code")
      end
    end
  end
end
