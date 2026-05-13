module Worlds
  class Propose
    class ConcurrentWorldLimitReached < StandardError; end

    def self.call(server:, organizer_admin:, name:, min_players:, t0_at:, slug: nil, auto_cancel_after_hours: nil)
      new(
        server: server,
        organizer_admin: organizer_admin,
        name: name,
        min_players: min_players,
        t0_at: t0_at,
        slug: slug,
        auto_cancel_after_hours: auto_cancel_after_hours
      ).call
    end

    def initialize(server:, organizer_admin:, name:, min_players:, t0_at:, slug:, auto_cancel_after_hours:)
      @server = server
      @organizer_admin = organizer_admin
      @name = name
      @min_players = min_players
      @t0_at = t0_at
      @slug = slug.presence || slugify(name)
      @auto_cancel_after_hours = auto_cancel_after_hours
    end

    def call
      enforce_concurrent_limit!

      attrs = {
        name: @name,
        slug: @slug,
        seed: SecureRandom.hex(8),
        status: "proposed",
        min_players: @min_players,
        t0_at: @t0_at
      }
      attrs[:auto_cancel_after_hours] = @auto_cancel_after_hours if @auto_cancel_after_hours.present?
      world = @server.worlds.create!(attrs)
      Worlds::StartJob.set(wait_until: world.t0_at).perform_later(world.id)
      world
    end

    private

    def enforce_concurrent_limit!
      limit = @server.max_concurrent_worlds
      if limit.zero?
        raise ConcurrentWorldLimitReached, "server #{@server.id} has world creation disabled (max_concurrent_worlds: 0)"
      end

      current = @server.worlds.where(status: World::LIVE_STATUSES).count
      return if current < limit

      raise ConcurrentWorldLimitReached, "server #{@server.id} already runs #{current} concurrent worlds (limit #{limit})"
    end

    def slugify(name)
      name.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "").slice(0, 40)
    end
  end
end
