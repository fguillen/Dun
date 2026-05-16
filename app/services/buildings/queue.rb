module Buildings
  class Queue
    class WorldNotBuildable < StandardError; end
    class KingdomEliminated < StandardError; end
    class UnknownBuilding < StandardError; end
    class InvalidTargetLevel < StandardError; end
    class TierGateUnmet < StandardError; end
    class QueueFull < StandardError; end
    class WonderInProgress < StandardError; end

    BUILDABLE_WORLD_STATUSES = %w[grace active].freeze

    def self.call(kingdom:, kind:, target_level:)
      new(kingdom: kingdom, kind: kind, target_level: target_level).call
    end

    def initialize(kingdom:, kind:, target_level:)
      @kingdom = kingdom
      @kind = kind.to_s
      @target_level = target_level.to_i
    end

    def call
      ActiveRecord::Base.transaction do
        kingdom = Kingdom.lock.find(@kingdom.id)

        raise UnknownBuilding, "unknown building #{@kind}" unless Catalog.kind?(@kind)
        raise WorldNotBuildable, "world status #{kingdom.world.status} not buildable" unless BUILDABLE_WORLD_STATUSES.include?(kingdom.world.status)
        raise KingdomEliminated, "kingdom eliminated" if kingdom.eliminated?
        if Wonders::LiveFor.call(kingdom).present?
          raise WonderInProgress, "build queue locked: a Wonder is in progress"
        end

        # Resolve any ripe completions first so slot count + tier gates reflect reality.
        Buildings::ResolveCompletions.call(kingdom)
        kingdom.reload

        building = kingdom.buildings.find_or_create_by!(kind: @kind) { |b| b.level = 0 }

        if @target_level != building.level + 1
          raise InvalidTargetLevel, "target_level must be #{building.level + 1}, got #{@target_level}"
        end
        if @target_level > Catalog::MAX_LEVEL
          raise InvalidTargetLevel, "target_level exceeds max level #{Catalog::MAX_LEVEL}"
        end

        # Idempotent retry: an identical in-progress order already exists.
        existing = kingdom.build_orders.in_progress.find_by(building_id: building.id, target_level: @target_level)
        return existing if existing

        enforce_tier_gates!(kingdom)
        enforce_queue_slot!(kingdom)

        cost = Buildings::CostFor.call(kind: @kind, level: @target_level)
        deltas = cost.transform_values { |amount| -amount }
        Stockpile::Apply.call(kingdom: kingdom, deltas: deltas)

        time = Buildings::TimeFor.call(kind: @kind, level: @target_level, kingdom: kingdom)
        now = Time.current
        order = BuildOrder.create!(
          kingdom: kingdom,
          building: building,
          target_level: @target_level,
          started_at: now,
          completes_at: now + time
        )

        ScheduledEvents::Schedule.call(
          world: kingdom.world,
          kind: "build_completion",
          fire_at: order.completes_at,
          payload: { "build_order_id" => order.id }
        )

        order
      end
    end

    private

    def enforce_tier_gates!(kingdom)
      gates = Catalog::TIER_GATES[@kind] or return
      gates.each do |required_kind, required_level|
        current = kingdom.buildings.where(kind: required_kind).pick(:level).to_i
        if current < required_level
          raise TierGateUnmet, "#{@kind} requires #{required_kind} level #{required_level} (have #{current})"
        end
      end
    end

    def enforce_queue_slot!(kingdom)
      town_hall_level = kingdom.buildings.where(kind: "town_hall").pick(:level).to_i
      max_slots = 1
      max_slots += 1 if town_hall_level >= 10
      max_slots += 1 if town_hall_level >= 20

      in_progress = kingdom.build_orders.in_progress.count
      if in_progress >= max_slots
        raise QueueFull, "queue full (#{in_progress}/#{max_slots})"
      end
    end
  end
end
