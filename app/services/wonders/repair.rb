module Wonders
  # Player-initiated repair. 1 HP per 8 Stone. Phase cap 2000 HP per phase
  # (independent per Foundation/Construction/Consecration). Pauses
  # construction 30 min per 500 HP repaired (stacks if already paused).
  class Repair
    class NotRepairable < StandardError; end
    class InvalidAmount < StandardError; end
    class CapReached < StandardError; end

    def self.call(wonder:, hp:)
      new(wonder: wonder, hp: hp.to_i).call
    end

    def initialize(wonder:, hp:)
      @wonder = wonder
      @hp_requested = hp
    end

    def call
      ActiveRecord::Base.transaction do
        wonder = Wonder.lock.find(@wonder.id)
        raise NotRepairable, "wonder status #{wonder.status} is not repairable" unless Wonder::LIVE_STATUSES.include?(wonder.status)
        raise InvalidAmount, "hp must be positive" if @hp_requested <= 0

        Wonders::ApplyConstruction.call(wonder: wonder)
        wonder.reload

        raise CapReached, "wonder already at target HP" if wonder.hp >= wonder.target_hp

        phase_key = current_phase_key(wonder)
        phase_used = wonder.repaired_hp_by_phase[phase_key].to_i
        cap_room = Wonder::PHASE_REPAIR_CAP - phase_used
        raise CapReached, "phase repair cap reached (#{phase_used}/#{Wonder::PHASE_REPAIR_CAP})" if cap_room <= 0

        effective = [ @hp_requested, wonder.target_hp - wonder.hp, cap_room ].min
        raise CapReached, "no room to repair" if effective <= 0

        cost_stone = effective * Wonder::REPAIR_STONE_PER_HP
        Stockpile::Apply.call(kingdom: wonder.kingdom, deltas: { "stone" => -cost_stone })

        pause_minutes = ((effective.to_f / 500).ceil) * Wonder::REPAIR_PAUSE_MINUTES_PER_500_HP
        now = Time.current
        base_pause = [ wonder.paused_until, now ].compact.max
        new_paused_until = base_pause + pause_minutes.minutes

        new_repaired = wonder.repaired_hp_by_phase.merge(phase_key => phase_used + effective)

        wonder.update!(
          hp: wonder.hp + effective,
          repaired_hp_by_phase: new_repaired,
          paused_until: new_paused_until
        )

        ActiveSupport::Notifications.instrument(
          "dun.wonder.repaired",
          world_id: wonder.kingdom.world_id,
          wonder_id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          hp_repaired: effective,
          stone_spent: cost_stone,
          paused_until: new_paused_until
        )

        wonder
      end
    end

    private

    def current_phase_key(wonder)
      wonder.status  # "foundation" | "construction" | "consecration"
    end
  end
end
