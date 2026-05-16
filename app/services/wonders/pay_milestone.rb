module Wonders
  # Explicit milestone payment (25/50/75%). The player must call this to
  # resume construction after ApplyConstruction has paused at the threshold.
  class PayMilestone
    class NoMilestonePending < StandardError; end
    class WrongPercent < StandardError; end
    class AlreadyPaid < StandardError; end

    def self.call(wonder:, percent:)
      new(wonder: wonder, percent: percent.to_i).call
    end

    def initialize(wonder:, percent:)
      @wonder = wonder
      @percent = percent
    end

    def call
      ActiveRecord::Base.transaction do
        wonder = Wonder.lock.find(@wonder.id)
        Wonders::ApplyConstruction.call(wonder: wonder)
        wonder.reload

        raise NoMilestonePending, "no milestone pending" unless wonder.pending_milestone_percent.present?
        raise WrongPercent, "wonder is at #{wonder.pending_milestone_percent}%, not #{@percent}%" if wonder.pending_milestone_percent != @percent
        raise AlreadyPaid, "milestone #{@percent}% already paid" if wonder.milestones_paid_for?(@percent)

        deltas = Wonders::Catalog.milestone_cost.transform_values { |amount| -amount }
        Stockpile::Apply.call(kingdom: wonder.kingdom, deltas: deltas)

        paid = wonder.milestones_paid.merge(@percent.to_s => true)
        wonder.update!(
          milestones_paid: paid,
          pending_milestone_percent: nil,
          last_construction_at: Time.current
        )

        ActiveSupport::Notifications.instrument(
          "dun.wonder.milestone_paid",
          world_id: wonder.kingdom.world_id,
          wonder_id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          percent: @percent
        )

        wonder
      end
    end
  end
end
