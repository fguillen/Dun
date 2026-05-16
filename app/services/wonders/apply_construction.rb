module Wonders
  # Lazy HP accrual — mirrors Stockpile::Read's philosophy. Each call advances
  # `hp` based on the elapsed time since `last_construction_at` (or
  # `paused_until` if later). Pauses on milestone thresholds and on repair
  # pauses; idempotent.
  class ApplyConstruction
    def self.call(wonder:, now: Time.current)
      new(wonder: wonder, now: now).call
    end

    def initialize(wonder:, now:)
      @wonder = wonder
      @now = now
    end

    def call
      return @wonder unless @wonder.status == "construction"
      return @wonder if @wonder.pending_milestone_percent.present?

      paused_until = @wonder.paused_until
      effective_start = [ @wonder.last_construction_at, paused_until ].compact.max
      return @wonder if paused_until && paused_until > @now
      return @wonder if effective_start && effective_start >= @now

      delta_hours = (@now - effective_start).to_f / 3600
      gained = (delta_hours * Wonder::CONSTRUCTION_HP_PER_HOUR).floor
      return @wonder if gained <= 0

      candidate = [ @wonder.hp + gained, Wonder::TARGET_HP ].min

      clamped_hp, pending_percent = clamp_to_milestone(@wonder.hp, candidate)

      attrs = { hp: clamped_hp, last_construction_at: @now }
      attrs[:pending_milestone_percent] = pending_percent if pending_percent

      @wonder.update!(attrs)
      @wonder
    end

    private

    # If candidate crosses an unpaid milestone threshold, clamp HP there and
    # return the percent that needs paying. Highest-percent crossed wins.
    def clamp_to_milestone(current_hp, candidate_hp)
      Wonder::MILESTONE_THRESHOLDS.each do |percent, threshold|
        next if @wonder.milestones_paid_for?(percent)
        next if current_hp >= threshold  # already crossed previously
        next if candidate_hp < threshold

        return [ threshold, percent.to_i ]
      end
      [ candidate_hp, nil ]
    end
  end
end
