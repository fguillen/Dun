require "test_helper"

module Servers
  class ConfigureTest < ActiveSupport::TestCase
    test "updates whitelisted attributes" do
      server = create(:server)

      Servers::Configure.call(server, name: "New Name", max_concurrent_worlds: 5)

      assert_equal "New Name", server.reload.name
      assert_equal 5, server.max_concurrent_worlds
    end

    test "ignores non-whitelisted attributes" do
      server = create(:server)
      original_slug = server.slug

      Servers::Configure.call(server, slug: "rogue-slug", owner_admin_id: 999)

      assert_equal original_slug, server.reload.slug
    end

    test "does not retroactively remove existing memberships when access narrows" do
      server = create(:server)
      domain = create(:server_access, server: server, kind: "domain", value: "*@example.com")
      player = create(:player, email: "alice@example.com")
      membership = ServerMembership.create!(server: server, player: player)

      domain.destroy!

      assert ServerMembership.exists?(membership.id), "existing membership must survive access removal"
    end
  end
end
