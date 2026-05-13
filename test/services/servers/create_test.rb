require "test_helper"

module Servers
  class CreateTest < ActiveSupport::TestCase
    test "creates the server and the owner adminship in one transaction" do
      admin = create(:admin)

      server = Servers::Create.call(owner_admin: admin, name: "Acme Co")

      assert server.persisted?
      assert_equal admin, server.owner
      assert_equal 1, server.server_adminships.count
      assert_equal "owner", server.server_adminships.first.role
    end

    test "auto-generates slug from name" do
      admin = create(:admin)
      server = Servers::Create.call(owner_admin: admin, name: "Acme Co!")
      assert_equal "acme-co", server.slug
    end

    test "accepts an explicit slug" do
      admin = create(:admin)
      server = Servers::Create.call(owner_admin: admin, name: "Acme Co", slug: "custom-slug")
      assert_equal "custom-slug", server.slug
    end
  end
end
