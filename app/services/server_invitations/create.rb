module ServerInvitations
  class Create
    def self.call(server:, email:)
      new(server: server, email: email).call
    end

    def initialize(server:, email:)
      @server = server
      @email = email.to_s.strip.downcase
    end

    def call
      ServerAccess.find_or_create_by!(server: @server, kind: "invite", value: @email)
    end
  end
end
