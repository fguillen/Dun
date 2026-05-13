module Admins
  class Invite
    def self.call(by_admin:, server:, email:)
      new(by_admin: by_admin, server: server, email: email).call
    end

    def initialize(by_admin:, server:, email:)
      @by_admin = by_admin
      @server = server
      @email = email.to_s.strip.downcase
    end

    def call
      ActiveRecord::Base.transaction do
        target = Admin.find_or_create_by!(email: @email) { |a| a.name = default_name }
        adminship = ServerAdminship.find_or_create_by!(server: @server, admin: target) do |row|
          row.role = "admin"
          row.granted_by_admin = @by_admin
        end
        adminship
      end
    end

    private

    def default_name
      @email.split("@").first.tr("._-", " ").split.map(&:capitalize).join(" ").presence || "Admin"
    end
  end
end
