module ScheduledEvents
  class Drain
    DEFAULT_BATCH = 500

    def self.call(now: Time.current, batch_size: DEFAULT_BATCH)
      new(now: now, batch_size: batch_size).call
    end

    def initialize(now:, batch_size:)
      @now = now
      @batch_size = batch_size
    end

    def call
      processed = 0

      loop do
        events = pull_batch
        break if events.empty?

        events.each { |event| safely_dispatch(event) }
        processed += events.size
        break if events.size < @batch_size
      end

      processed
    end

    private

    def pull_batch
      ScheduledEvent.transaction do
        ScheduledEvent.ripe(@now)
          .order(:fire_at, :id)
          .limit(@batch_size)
          .lock("FOR UPDATE SKIP LOCKED")
          .to_a
      end
    end

    def safely_dispatch(event)
      ScheduledEvents::Dispatch.call(event)
    rescue => e
      Rails.logger.warn(
        event: "scheduled_events.dispatch_failed",
        scheduled_event_id: event.id,
        kind: event.kind,
        error_class: e.class.name,
        error_message: e.message
      )
    end
  end
end
