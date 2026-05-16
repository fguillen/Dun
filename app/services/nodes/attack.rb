module Nodes
  # Contested capture of a node already owned by another kingdom. The
  # wilderness garrison is gone (one-time §16.5), so combat resolves against
  # whatever defending armies the owner has parked at the node's region. If
  # there are no defenders, the attacker takes the node immediately.
  class Attack
    class CatapultRequired < StandardError; end
    class NotOwned < StandardError; end
    class SelfAttack < StandardError; end

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
      raise NotOwned, "node #{@node.id} is wilderness — use Nodes::Capture" if @node.wilderness?

      army = Army.find(@march_order.army_id)
      raise SelfAttack, "kingdom #{army.kingdom_id} already owns node #{@node.id}" if @node.owner_kingdom_id == army.kingdom_id
      raise CatapultRequired, "node attack requires a catapult (§9)" if army.composition["catapult"].to_i < 1

      defender_kingdom = Kingdom.find(@node.owner_kingdom_id)
      defender_armies_present = defender_kingdom.armies
        .where(location_region_id: @node.region_id, status: %w[home engaged])
        .exists?

      if defender_armies_present
        battle = Combat::Resolve.call(march_order: @march_order, defender_kingdom: defender_kingdom, rng: @rng)
        if battle && ATTACKER_WIN.include?(battle.outcome)
          transfer_ownership(army.kingdom_id, battle: battle)
        end
        battle
      else
        # Undefended: walk in and take it.
        army.update!(status: "home", location_region_id: @node.region_id)
        transfer_ownership(army.kingdom_id, battle: nil)
        nil
      end
    end

    private

    def transfer_ownership(new_owner_id, battle:)
      @node.update!(owner_kingdom_id: new_owner_id)
      Kingdoms::BumpPeakNodes.call(kingdom_id: new_owner_id)
      ActiveSupport::Notifications.instrument(
        "dun.node.captured",
        world_id: @node.region.world_id,
        region_id: @node.region_id,
        node_id: @node.id,
        kingdom_id: new_owner_id,
        battle_id: battle&.id
      )
    end
  end
end
