module MagicLinks
  class Request
    SCOPES = { "player" => "Player", "admin" => "Admin" }.freeze

    def self.call(email:, scope:)
      new(email: email, scope: scope).call
    end

    def initialize(email:, scope:)
      @email = email.to_s.strip.downcase
      @scope = scope.to_s
      @owner_type = SCOPES.fetch(@scope) { raise ArgumentError, "unknown scope: #{scope.inspect}" }
    end

    def call
      record, raw_token = MagicLink.generate_for(owner_type: @owner_type, email: @email)
      MagicLinkMailer
        .with(email: @email, raw_token: raw_token, scope: @scope)
        .send_link
        .deliver_later
      record
    end
  end
end
