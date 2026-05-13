module Worlds
  class Cancel
    class WorldNotCancellable < StandardError; end

    def self.call(world, by_admin:)
      new(world, by_admin: by_admin).call
    end

    def initialize(world, by_admin:)
      @world = world
      @by_admin = by_admin
    end

    def call
      raise WorldNotCancellable, "world is #{@world.status}; only proposed worlds can be cancelled" unless @world.proposed?

      @world.update!(status: "cancelled", cancelled_at: Time.current)
      @world
    end
  end
end
