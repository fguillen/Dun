module Worlds
  class Configure
    class WorldNotConfigurable < StandardError; end

    ALLOWED = %i[name min_players t0_at auto_cancel_after_hours].freeze

    def self.call(world, attrs)
      new(world, attrs).call
    end

    def initialize(world, attrs)
      @world = world
      @attrs = attrs.to_h.symbolize_keys.slice(*ALLOWED)
    end

    def call
      raise WorldNotConfigurable, "world is #{@world.status}; only proposed worlds can be configured" unless @world.proposed?

      @world.update!(@attrs)
      @world
    end
  end
end
