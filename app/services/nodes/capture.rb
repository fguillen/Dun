module Nodes
  # Wilderness node capture: attacker fights the static garrison stored on the
  # node, and on victory takes ownership. Garrison defeat is one-time (§16.5)
  # — only a winning attempt clears the garrison; routs and losses leave the
  # node untouched for the next attacker.
  class Capture
    class CatapultRequired < StandardError; end
    class AlreadyOwned < StandardError; end

    ATTACKER_WIN = Combat::ApplyOutcome::ATTACKER_WIN

    def self.call(march_order:, node:, rng: Random.new)
      new(march_order: march_order, node: node, rng: rng).call
    end

    def initialize(march_order:, node:, rng:)
      @march_order = march_order
      @node = node
      @rng = rng
    end

    def call
      raise AlreadyOwned, "node #{@node.id} already owned" unless @node.wilderness?

      army = Army.find(@march_order.army_id)
      raise CatapultRequired, "capture requires a catapult (§9)" if army.composition["catapult"].to_i < 1

      battle = Combat::ResolveGarrison.call(march_order: @march_order, garrison: @node.garrison, rng: @rng)
      return nil if battle.nil?

      if ATTACKER_WIN.include?(battle.outcome)
        @node.update!(owner_kingdom_id: army.kingdom_id, garrison: {})
        Kingdoms::BumpPeakNodes.call(kingdom_id: army.kingdom_id)
        ActiveSupport::Notifications.instrument(
          "dun.node.captured",
          world_id: battle.world_id,
          region_id: battle.region_id,
          node_id: @node.id,
          kingdom_id: army.kingdom_id,
          battle_id: battle.id
        )
      end

      battle
    end
  end
end
