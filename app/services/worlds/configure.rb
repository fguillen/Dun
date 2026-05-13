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

      previous_t0 = @world.t0_at
      @world.update!(@attrs)
      if @attrs.key?(:t0_at) && @world.t0_at != previous_t0
        Worlds::StartJob.set(wait_until: @world.t0_at).perform_later(@world.id)
      end
      @world
    end
  end
end
