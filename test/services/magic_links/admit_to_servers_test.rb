require "test_helper"

module MagicLinks
  class AdmitToServersTest < ActiveSupport::TestCase
    test "consume admits the new Player to every server whose access matches their email" do
      acme = create(:server)
      create(:server_access, server: acme, kind: "domain", value: "*@acme.com")

      contoso = create(:server)
      create(:server_access, server: contoso, kind: "invite", value: "alice@acme.com")

      other = create(:server)
      create(:server_access, server: other, kind: "domain", value: "*@other.com")

      _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@acme.com")
      result = MagicLinks::Consume.call(raw_token: raw_token, scope: "player")

      assert ServerMembership.exists?(server: acme,   player: result.owner)
      assert ServerMembership.exists?(server: contoso, player: result.owner)
      assert_not ServerMembership.exists?(server: other, player: result.owner)
    end

    test "consume does not duplicate memberships for re-admission" do
      server = create(:server)
      create(:server_access, server: server, kind: "domain", value: "*@example.com")
      player = create(:player, email: "alice@example.com")
      ServerMembership.create!(server: server, player: player)

      _record, raw_token = MagicLink.generate_for(owner_type: "Player", email: "alice@example.com")

      assert_no_difference -> { ServerMembership.count } do
        MagicLinks::Consume.call(raw_token: raw_token, scope: "player")
      end
    end

    test "consuming an admin-scope link does not create player memberships" do
      server = create(:server)
      create(:server_access, server: server, kind: "domain", value: "*@example.com")

      _record, raw_token = MagicLink.generate_for(owner_type: "Admin", email: "boss@example.com")

      MagicLinks::Consume.call(raw_token: raw_token, scope: "admin")

      assert_equal 0, ServerMembership.count
    end
  end
end
