require "test_helper"

class ServerTest < ActiveSupport::TestCase
  test "factory creates a server with the owner as the first adminship" do
    server = create(:server)

    assert_equal 1, server.server_adminships.size
    assert_equal server.owner, server.server_adminships.first.admin
    assert_equal "owner", server.server_adminships.first.role
  end

  test "slug uniqueness is case-insensitive" do
    create(:server, slug: "acme")
    dup = build(:server, slug: "ACME")

    assert_not dup.valid?
  end

  test "slug format rejects invalid characters" do
    server = build(:server, slug: "no spaces")
    assert_not server.valid?
  end

  test "default world limits are 2/2" do
    server = create(:server)

    assert_equal 2, server.max_concurrent_worlds
    assert_equal 2, server.max_worlds_per_account
  end

  test "admits? delegates to ServerAccess.admits?" do
    server = create(:server)
    create(:server_access, server: server, kind: "domain", value: "*@example.com")

    assert server.admits?("alice@example.com")
    assert_not server.admits?("alice@other.com")
  end
end
