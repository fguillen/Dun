module Caravans
  # Combat between the caravan escort and a hostile army present at the
  # destination region. The hostile is the defender for combat purposes; the
  # escort is the attacker (their march just arrived). Combat::Resolve receives
  # `defender_army:` so it skips region-home-kingdom defender aggregation and
  # walls/home bonus (escort is "in the open").
  #
  # Outcome handling:
  #   - escort wins (attacker_victory / defender_rout) → cargo continues; call
  #     Caravans::Deliver. No loot transfer (loot is the caravan cargo, handled
  #     here, not by Combat::ApplyEscortOutcome which intentionally clears loot).
  #   - escort loses (defender_victory / attacker_rout) → hostile takes the
  #     cargo, capped by their surviving carrying capacity and then their
  #     home Warehouse cap (excess silently lost, per §16.11 ruin parity).
  class Intercept
    ESCORT_WIN = %w[attacker_victory defender_rout].freeze

    def self.call(caravan:, attacker_army:, rng: Random.new)
      new(caravan: caravan, attacker_army: attacker_army, rng: rng).call
    end

    def initialize(caravan:, attacker_army:, rng:)
      @caravan = caravan
      @hostile = attacker_army
      @rng = rng
    end

    def call
      ActiveRecord::Base.transaction do
        caravan = Caravan.lock.find(@caravan.id)
        return caravan unless caravan.in_transit?

        escort = caravan.escort_army
        # Edge: escort somehow gone — treat as auto-loss to the hostile.
        if escort.nil? || Army.find(escort.id).empty?
          finish_loss(caravan, nil)
          return caravan.reload
        end

        # Combat::Resolve: escort is "attacker" (its march just arrived); hostile
        # is the explicit defender_army. Resolve will route to ApplyEscortOutcome
        # which clears loot and updates positions/compositions.
        battle = Combat::Resolve.call(
          march_order: caravan.outbound_march_order,
          defender_army: @hostile,
          rng: @rng
        )

        if battle.nil?
          # The hostile was empty too — caravan walks in unopposed.
          Caravans::Deliver.call(caravan: caravan)
          return caravan.reload
        end

        if ESCORT_WIN.include?(battle.outcome)
          Caravans::Deliver.call(caravan: caravan)
        else
          finish_loss(caravan, battle)
        end

        caravan.reload
      end
    end

    private

    def finish_loss(caravan, battle)
      loot = compute_loot(caravan, battle)

      if loot.values.any? { |v| v.positive? }
        Stockpile::Apply.call(kingdom: @hostile.kingdom, deltas: loot)
      end

      now = Time.current
      caravan.update!(status: "intercepted", intercepted_at: now)

      attacker_handle = @hostile.kingdom.handle
      TradeLedger::Record.call(caravan: caravan, status: "intercepted", attacker_handle: attacker_handle)

      ActiveSupport::Notifications.instrument(
        "dun.caravan.intercepted",
        world_id: caravan.world_id,
        caravan_id: caravan.id,
        sender_kingdom_id: caravan.sender_kingdom_id,
        receiver_kingdom_id: caravan.receiver_kingdom_id,
        interceptor_kingdom_id: @hostile.kingdom_id,
        battle_id: battle&.id,
        loot_taken: loot
      )
    end

    def compute_loot(caravan, battle)
      capacity = surviving_capacity(battle)
      remaining = capacity
      caravan.payload.each_with_object(Hash.new(0)) do |(resource, amount), out|
        next if remaining <= 0
        take = [ amount.to_i, remaining ].min
        out[resource] = take
        remaining -= take
      end
    end

    def surviving_capacity(battle)
      # Use the hostile's ending composition from the battle (survivors after
      # the fight). If no battle (escort gone), use full hostile composition.
      composition = if battle
        participant = battle.participants.find_by(side: "defender", army_id: @hostile.id)
        participant&.ending_composition || @hostile.composition
      else
        @hostile.composition
      end

      composition.sum { |unit, count| Units::Catalog.capacity_for(unit) * count.to_i }
    end
  end
end
