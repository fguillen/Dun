module Admins
  class RevokeAdminship
    def self.call(by_admin:, target_admin:, server:)
      new(by_admin: by_admin, target_admin: target_admin, server: server).call
    end

    def initialize(by_admin:, target_admin:, server:)
      @by_admin = by_admin
      @target_admin = target_admin
      @server = server
    end

    def call
      ActiveRecord::Base.transaction do
        adminship = ServerAdminship.find_by!(server: @server, admin: @target_admin)
        raise LastAdminError if ServerAdminship.count_admins(@server) <= 1

        adminship.destroy!
        adminship
      end
    end
  end
end
