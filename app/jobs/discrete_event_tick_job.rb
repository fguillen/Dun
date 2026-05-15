class DiscreteEventTickJob < ApplicationJob
  queue_as :default

  def perform
    ScheduledEvents::Drain.call
  end
end
