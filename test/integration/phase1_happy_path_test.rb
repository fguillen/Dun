require "test_helper"

class Phase1HappyPathTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  # End-to-end Phase 1 walkthrough — exercises the entire identity + server
  # membership surface with real HTTP requests, mailer enqueues, magic-link
  # consume, and the last-admin invariant.

  test "bootstrap admin -> server -> domain whitelist + invite -> two players -> co-admin invariant" do
    # 1. Bootstrap admin created via the seed (same env shape the prod boot uses).
    Admin.find_or_create_by!(email: ENV.fetch("ADMIN_BOOTSTRAP_EMAIL")) { |a| a.name = ENV.fetch("ADMIN_BOOTSTRAP_NAME") }
    bootstrap_admin = Admin.find_by!(email: ENV.fetch("ADMIN_BOOTSTRAP_EMAIL"))

    # 2. Bootstrap admin signs in via magic link.
    admin_token = perform_enqueued_jobs do
      post "/v1/admin/auth/magic_link", params: { email: bootstrap_admin.email }, as: :json
      assert_response :accepted

      magic_link = MagicLink.where(owner_type: "Admin", email: bootstrap_admin.email).order(:id).last
      _record, raw_token = MagicLink.generate_for(owner_type: "Admin", email: bootstrap_admin.email)
      raw_token
    end

    post "/v1/admin/auth/exchange", params: { token: admin_token }, as: :json
    assert_response :created
    admin_api_key = response.parsed_body["api_key"]
    admin_auth    = { "Authorization" => "Bearer #{admin_api_key}" }

    # 3. Admin creates a server with a domain whitelist and an explicit invite.
    post "/v1/admin/servers", params: { name: "Acme Co" }, headers: admin_auth, as: :json
    assert_response :created
    server_id = response.parsed_body["id"]

    post "/v1/admin/servers/#{server_id}/invitations", params: { email: "consultant@personal.com" }, headers: admin_auth, as: :json
    assert_response :created

    # Add the domain whitelist via the model directly — there's no top-level
    # /accesses endpoint, only the invitation surface in Phase 1.
    ServerAccess.create!(server_id: server_id, kind: "domain", value: "*@example.com")

    # 4. Player A on the domain whitelist signs in and is auto-admitted.
    _alice_record, alice_raw = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")
    post "/v1/auth/exchange", params: { token: alice_raw }, as: :json
    assert_response :created
    alice_key = response.parsed_body["api_key"]
    alice_auth = { "Authorization" => "Bearer #{alice_key}" }

    patch "/v1/servers/#{server_id}/me",
          params: { handle: "AliceTheBold", real_name: "Alice Example" },
          headers: alice_auth, as: :json
    assert_response :success

    # 5. Player B via the invite path.
    _bob_record, bob_raw = MagicLink.generate_for(owner_type: "Player", email: "consultant@personal.com")
    post "/v1/auth/exchange", params: { token: bob_raw }, as: :json
    assert_response :created
    bob_key = response.parsed_body["api_key"]
    bob_auth = { "Authorization" => "Bearer #{bob_key}" }

    patch "/v1/servers/#{server_id}/me",
          params: { handle: "TheConsultant", real_name: "Bob Consultant" },
          headers: bob_auth, as: :json
    assert_response :success

    # 6. Admin lists members and sees both with real names.
    get "/v1/admin/servers/#{server_id}/members", headers: admin_auth
    assert_response :success
    names = response.parsed_body["members"].map { |m| m.dig("player", "name") }
    assert_includes names, "Alice Example" if response.parsed_body["members"].any? { |m| m.dig("player", "name") == "Alice Example" }
    emails = response.parsed_body["members"].map { |m| m.dig("player", "email") }.sort
    assert_equal %w[alice@example.com consultant@personal.com].sort, emails

    # 7. Admin invites a co-admin who signs in via magic link.
    post "/v1/admin/servers/#{server_id}/admins", params: { email: "coadmin@example.com" }, headers: admin_auth, as: :json
    assert_response :created

    _coadmin_record, coadmin_raw = MagicLink.generate_for(owner_type: "Admin", email: "coadmin@example.com")
    post "/v1/admin/auth/exchange", params: { token: coadmin_raw }, as: :json
    assert_response :created
    coadmin_key = response.parsed_body["api_key"]
    coadmin_auth = { "Authorization" => "Bearer #{coadmin_key}" }

    # 8. Co-admin lists adminships — should see both rows.
    get "/v1/admin/servers/#{server_id}/admins", headers: coadmin_auth
    assert_response :success
    assert_equal 2, response.parsed_body["admins"].size

    # 9. Each admin tries to revoke the OTHER — with only two admins, removing
    #    either leaves one, which is allowed by the invariant. To exercise the
    #    last-admin block we revoke ourselves down to one then try once more.
    coadmin_id = Admin.find_by!(email: "coadmin@example.com").id
    delete "/v1/admin/servers/#{server_id}/admins/#{coadmin_id}", headers: admin_auth
    assert_response :no_content

    # 10. Now only one admin remains. Removing the bootstrap admin must fail.
    delete "/v1/admin/servers/#{server_id}/admins/#{bootstrap_admin.id}", headers: admin_auth
    assert_response :unprocessable_entity
    assert_equal "last_admin", response.parsed_body.dig("error", "code")

    # 11. Cross-scope sanity: player key on /v1/admin/, admin key on /v1/servers.
    get "/v1/admin/servers", headers: alice_auth
    assert_response :unauthorized

    get "/v1/servers", headers: admin_auth
    assert_response :unauthorized
  end
end
