module ScheduledEvents
  class Schedule
    def self.call(world:, kind:, fire_at:, payload: {})
      new(world: world, kind: kind, fire_at: fire_at, payload: payload).call
    end

    def initialize(world:, kind:, fire_at:, payload:)
      @world = world
      @kind = kind.to_s
      @fire_at = fire_at
      @payload = payload || {}
    end

    def call
      event = ScheduledEvent.create!(
        world: @world,
        kind: @kind,
        payload: @payload.deep_stringify_keys,
        fire_at: @fire_at
      )

      ActiveSupport::Notifications.instrument(
        "dun.scheduled_event.created",
        event_id: event.id,
        world_id: event.world_id,
        kind: event.kind,
        fire_at: event.fire_at
      )

      event
    end
  end
end
