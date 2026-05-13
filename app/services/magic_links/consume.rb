module MagicLinks
  class Consume
    class InvalidToken < StandardError; end
    class ScopeMismatch < StandardError; end

    SCOPES = { "player" => Player, "admin" => Admin }.freeze

    Result = Struct.new(:owner, :api_key, :raw_token, keyword_init: true)

    def self.call(raw_token:, scope:)
      new(raw_token: raw_token, scope: scope).call
    end

    def initialize(raw_token:, scope:)
      @raw_token = raw_token.to_s
      @scope = scope.to_s
      @owner_class = SCOPES.fetch(@scope) { raise ArgumentError, "unknown scope: #{scope.inspect}" }
    end

    def call
      link = MagicLink.find_by_token(@raw_token) or raise InvalidToken
      raise ScopeMismatch unless link.owner_type == @owner_class.name

      ActiveRecord::Base.transaction do
        owner = @owner_class.find_or_create_by!(email: link.email) { |r| r.name = default_name(link.email) }
        link.consume!(owner: owner)
        admit_to_servers(owner) if owner.is_a?(Player)
        api_key, raw = ApiKey.generate_for(owner: owner)
        Result.new(owner: owner, api_key: api_key, raw_token: raw)
      end
    end

    private

    def default_name(email)
      email.split("@").first.tr("._-", " ").split.map(&:capitalize).join(" ").presence || "Player"
    end

    def admit_to_servers(player)
      Server.find_each do |server|
        next unless server.admits?(player.email)

        ServerMembership.find_or_create_by!(server: server, player: player)
        PlayerProfile.find_or_create_by!(server: server, player: player)
      end
    end
  end
end
