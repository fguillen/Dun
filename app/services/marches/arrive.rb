module Marches
  class Arrive
    def self.call(march_order:)
      new(march_order: march_order).call
    end

    def initialize(march_order:)
      @march_order = march_order
    end

    def call
      ActiveRecord::Base.transaction do
        order = MarchOrder.lock.find(@march_order.id)
        return order if order.resolved?

        army = Army.lock.find(order.army_id)
        target = Region.find(order.target_region_id)

        case order.intent
        when "reinforce"
          handle_reinforce(army, target)
        when "scout"
          handle_scout(army, target)
        when "attack"
          handle_attack(army, target, order)
        when "capture"
          handle_capture(army, target, order)
        when "claim_ruin"
          handle_claim_ruin(army, target, order)
        when "caravan"
          handle_caravan(order)
        when "caravan_return"
          handle_caravan_return(army, target, order)
        end

        order.update!(arrived_at: Time.current)
        mark_scheduled_event_processed(order)

        ActiveSupport::Notifications.instrument(
          "dun.march_order.arrived",
          world_id: army.kingdom.world_id,
          march_order_id: order.id,
          intent: order.intent
        )

        order
      end
    end

    private

    def handle_reinforce(army, target)
      army.update!(status: "home", location_region_id: target.id)
    end

    # Phase 7 will write a Scout report on arrival; for now the scout returns
    # to a "returning" status at the target so subsequent recall logic can
    # bring it home cleanly.
    def handle_scout(army, target)
      army.update!(status: "returning", location_region_id: target.id)
    end

    # Phase 6 — `attack` resolves a battle against the target region's home
    # kingdom (if any). If there is no defender at the region, Combat::Resolve
    # returns nil and we walk the attacker in unopposed. On a real combat,
    # Combat::ApplyOutcome has already set the army's final status/location.
    def handle_attack(army, target, order)
      battle = Combat::Resolve.call(march_order: order)
      return battle if battle
      army.update!(status: "home", location_region_id: target.id)
      nil
    end

    # Phase 7 — `capture` arrives at a region containing a Node. Wilderness
    # nodes are fought through `Nodes::Capture` (vs static garrison); enemy-
    # owned nodes route through `Nodes::Attack` (PvP at the region, or walk-in
    # if undefended). If the army has no catapult (or the target has no node)
    # the attacker parks `engaged` and emits an aborted notification.
    def handle_capture(army, target, order)
      node = Node.where(region_id: target.id).first
      if node.nil?
        ActiveSupport::Notifications.instrument(
          "dun.node.capture_aborted",
          world_id: army.kingdom.world_id,
          region_id: target.id,
          army_id: army.id,
          reason: "no_node"
        )
        army.update!(status: "home", location_region_id: target.id)
        return nil
      end

      service = node.wilderness? ? Nodes::Capture : Nodes::Attack
      service.call(march_order: order, node: node)
    rescue Nodes::Capture::CatapultRequired, Nodes::Attack::CatapultRequired
      army.update!(status: "engaged", location_region_id: target.id)
      ActiveSupport::Notifications.instrument(
        "dun.node.capture_aborted",
        world_id: army.kingdom.world_id,
        region_id: target.id,
        army_id: army.id,
        reason: "catapult_required"
      )
      nil
    end

    # Phase 7 — `claim_ruin` arrives at a region containing a Ruin. The ruin's
    # one-time garrison is fought via `Ruins::Claim`; cache is granted on
    # victory (capped by warehouse, excess lost per §16.11).
    def handle_claim_ruin(army, target, order)
      ruin = Ruin.unclaimed.where(region_id: target.id).first
      if ruin.nil?
        ActiveSupport::Notifications.instrument(
          "dun.ruin.claim_aborted",
          world_id: army.kingdom.world_id,
          region_id: target.id,
          army_id: army.id,
          reason: "no_unclaimed_ruin"
        )
        army.update!(status: "home", location_region_id: target.id)
        return nil
      end

      Ruins::Claim.call(march_order: order, ruin: ruin)
    end

    # Phase 8 — `caravan` arrives at the receiver's home region. Caravans::Arrive
    # routes to Deliver or Intercept (if any third-party army is camped at the
    # destination). Deliver schedules a `caravan_return` march so the escort
    # retraces home; Intercept resolves combat and consumes the cargo.
    def handle_caravan(order)
      caravan = Caravan.find_by(outbound_march_order_id: order.id)
      return if caravan.nil?
      Caravans::Arrive.call(caravan: caravan)
    end

    # Phase 8 — `caravan_return` is the escort retracing back to the sender.
    # On arrival, Caravans::CompleteReturn merges its survivors into the
    # sender's home army (and disposes of the temp escort Army row).
    def handle_caravan_return(army, target, order)
      caravan = Caravan.find_by(return_march_order_id: order.id)
      if caravan.nil?
        # No linked caravan (shouldn't happen) — fall back to a plain reinforce.
        army.update!(status: "home", location_region_id: target.id)
        return
      end
      Caravans::CompleteReturn.call(caravan: caravan)
    end

    def mark_scheduled_event_processed(order)
      event = ScheduledEvent.pending
        .where(kind: "march_arrival")
        .where("payload->>'march_order_id' = ?", order.id)
        .first
      event&.update!(processed_at: Time.current)
    end
  end
end
