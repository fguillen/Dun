require "test_helper"

class ServerAccessTest < ActiveSupport::TestCase
  setup { @server = create(:server) }

  test "admits? returns false when no access rules exist" do
    assert_not ServerAccess.admits?(@server, "anyone@example.com")
    assert_not ServerAccess.admits?(@server, "")
    assert_not ServerAccess.admits?(@server, nil)
  end

  test "domain access admits matching email" do
    create(:server_access, server: @server, kind: "domain", value: "*@example.com")

    assert ServerAccess.admits?(@server, "alice@example.com")
    assert ServerAccess.admits?(@server, "ALICE@EXAMPLE.COM")
    assert_not ServerAccess.admits?(@server, "alice@other.com")
  end

  test "wildcard subdomain pattern" do
    create(:server_access, server: @server, kind: "domain", value: "*@*.acme.com")

    assert ServerAccess.admits?(@server, "alice@eng.acme.com")
    assert ServerAccess.admits?(@server, "bob@hr.acme.com")
    assert_not ServerAccess.admits?(@server, "alice@acme.com") # no subdomain
  end

  test "invite access admits exact email match" do
    create(:server_access, server: @server, kind: "invite", value: "Consultant@example.org")

    assert ServerAccess.admits?(@server, "consultant@example.org")
    assert_not ServerAccess.admits?(@server, "other@example.org")
  end

  test "union of domain + invite" do
    create(:server_access, server: @server, kind: "domain", value: "*@acme.com")
    create(:server_access, server: @server, kind: "invite", value: "guest@personal.com")

    assert ServerAccess.admits?(@server, "alice@acme.com")
    assert ServerAccess.admits?(@server, "guest@personal.com")
    assert_not ServerAccess.admits?(@server, "other@personal.com")
  end

  test "domain value must contain @" do
    access = build(:server_access, server: @server, kind: "domain", value: "acme.com")
    assert_not access.valid?
    assert_includes access.errors[:value], "must include @"
  end

  test "invite value must be a valid email" do
    access = build(:server_access, server: @server, kind: "invite", value: "not-an-email")
    assert_not access.valid?
  end

  test "uniqueness is scoped to (server, kind)" do
    create(:server_access, server: @server, kind: "invite", value: "guest@personal.com")
    dup = build(:server_access, server: @server, kind: "invite", value: "guest@personal.com")

    assert_not dup.valid?

    # same value across (server, kind) categories is allowed
    same_value_diff_kind = build(:server_access, server: @server, kind: "domain", value: "guest@personal.com")
    assert same_value_diff_kind.valid?
  end
end
