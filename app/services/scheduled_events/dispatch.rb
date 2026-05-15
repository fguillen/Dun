module ScheduledEvents
  class Dispatch
    class UnknownKind < StandardError; end

    HANDLERS = {
      "build_completion" => ->(event) {
        build_order = BuildOrder.find_by(id: event.payload["build_order_id"])
        Buildings::Complete.call(build_order: build_order) if build_order
      },
      "grace_expiry" => ->(event) {
        Worlds::EndGrace.call(event.world)
      }
    }.freeze

    def self.call(event)
      new(event).call
    end

    def initialize(event)
      @event = event
    end

    def call
      return @event unless @event.pending?

      handler = HANDLERS[@event.kind]
      raise UnknownKind, "no handler registered for kind #{@event.kind.inspect}" if handler.nil?

      ActiveSupport::Notifications.instrument(
        "dun.scheduled_event.processed",
        event_id: @event.id,
        world_id: @event.world_id,
        kind: @event.kind
      ) do
        handler.call(@event)
        @event.update!(processed_at: Time.current)
      end

      @event
    end
  end
end
