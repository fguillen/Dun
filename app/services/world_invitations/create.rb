module WorldInvitations
  class Create
    def self.call(world:, by_admin:, email:)
      new(world: world, by_admin: by_admin, email: email).call
    end

    def initialize(world:, by_admin:, email:)
      @world = world
      @by_admin = by_admin
      @email = email.to_s.strip.downcase
    end

    def call
      @world.world_invitations.find_or_create_by!(email: @email) do |inv|
        inv.invited_by_admin = @by_admin
      end
    end
  end
end
