module Servers
  class Create
    def self.call(owner_admin:, name:, slug: nil)
      new(owner_admin: owner_admin, name: name, slug: slug).call
    end

    def initialize(owner_admin:, name:, slug:)
      @owner_admin = owner_admin
      @name = name
      @slug = slug.presence || slugify(name)
    end

    def call
      ActiveRecord::Base.transaction do
        server = Server.create!(name: @name, slug: @slug, owner: @owner_admin)
        ServerAdminship.create!(server: server, admin: @owner_admin, role: "owner")
        server
      end
    end

    private

    def slugify(name)
      name.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "").slice(0, 40)
    end
  end
end
