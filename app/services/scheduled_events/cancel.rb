module ScheduledEvents
  class Cancel
    def self.call(event)
      new(event).call
    end

    def initialize(event)
      @event = event
    end

    def call
      return @event if @event.nil?
      return @event unless @event.pending?

      @event.update!(processed_at: Time.current)
      @event
    end
  end
end
