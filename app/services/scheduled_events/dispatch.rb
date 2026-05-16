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
      },
      "training_completion" => ->(event) {
        training_order = TrainingOrder.find_by(id: event.payload["training_order_id"])
        Training::Complete.call(training_order: training_order) if training_order
      },
      "march_arrival" => ->(event) {
        march_order = MarchOrder.find_by(id: event.payload["march_order_id"])
        Marches::Arrive.call(march_order: march_order) if march_order
      },
      "wonder_phase" => ->(event) {
        wonder = Wonder.find_by(id: event.payload["wonder_id"])
        next unless wonder
        case event.payload["transition"]
        when "enter_consecration" then Wonders::EnterConsecration.call(wonder: wonder)
        when "complete"           then Wonders::Complete.call(wonder: wonder)
        end
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

      if world_frozen?
        @event.update!(processed_at: Time.current)
        ActiveSupport::Notifications.instrument(
          "dun.scheduled_event.skipped_world_archived",
          event_id: @event.id,
          world_id: @event.world_id,
          kind: @event.kind
        )
        return @event
      end

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

    private

    def world_frozen?
      world = @event.world
      world.archived? || world.cancelled?
    end
  end
end
