module Nodes
  # Single entry point for taking a node, regardless of who defends it:
  #
  #   * Wilderness node  -> fight the static NPC garrison (Combat::ResolveGarrison).
  #     Garrison defeat is one-time (§16.5): only a winning attempt clears it; routs
  #     and losses leave the node untouched for the next attacker.
  #   * Owned node       -> fight the owner's defending armies at the region
  #     (Combat::Resolve), or walk in unopposed if there are none.
  #
  # Home-hoard nodes are reserved for their home kingdom: only the kingdom whose
  # home_region is that node's region may capture it (in any state). Everyone else
  # is rejected — see HomeHoardProtected.
  class Capture
    class CatapultRequired < StandardError; end
    class SelfCapture < StandardError; end
    class HomeHoardProtected < StandardError; end

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
      army = Army.find(@march_order.army_id)
      raise SelfCapture, "kingdom #{army.kingdom_id} already owns node #{@node.id}" if @node.owner_kingdom_id == army.kingdom_id
      raise HomeHoardProtected, "node #{@node.id} is a home-hoard reserved for its home kingdom" if foreign_home_hoard?(army.kingdom_id)
      raise CatapultRequired, "capture requires a catapult (§9)" if army.composition["catapult"].to_i < 1

      @node.wilderness? ? capture_wilderness(army) : capture_owned(army)
    end

    private

    # True when the node is a home-hoard and the acting kingdom is not the one that
    # spawned in its region. An unclaimed spawn slot (no home kingdom yet) is locked
    # for everyone until it is assigned.
    def foreign_home_hoard?(kingdom_id)
      return false unless @node.is_home_hoard?
      rightful = Kingdom.find_by(world_id: @node.region.world_id, home_region_id: @node.region_id)
      rightful.nil? || rightful.id != kingdom_id
    end

    def capture_wilderness(army)
      battle = Combat::ResolveGarrison.call(march_order: @march_order, garrison: @node.garrison, rng: @rng)
      return nil if battle.nil?

      if ATTACKER_WIN.include?(battle.outcome)
        @node.update!(owner_kingdom_id: army.kingdom_id, garrison: {})
        Kingdoms::BumpPeakNodes.call(kingdom_id: army.kingdom_id)
        instrument_captured(kingdom_id: army.kingdom_id, battle: battle)
      end

      battle
    end

    def capture_owned(army)
      defender_kingdom = Kingdom.find(@node.owner_kingdom_id)
      defender_armies_present = defender_kingdom.armies
        .where(location_region_id: @node.region_id, status: %w[home engaged])
        .exists?

      if defender_armies_present
        battle = Combat::Resolve.call(march_order: @march_order, defender_kingdom: defender_kingdom, rng: @rng)
        transfer_ownership(army.kingdom_id, battle: battle) if battle && ATTACKER_WIN.include?(battle.outcome)
        battle
      else
        army.update!(status: "home", location_region_id: @node.region_id)
        transfer_ownership(army.kingdom_id, battle: nil)
        nil
      end
    end

    def transfer_ownership(new_owner_id, battle:)
      @node.update!(owner_kingdom_id: new_owner_id)
      Kingdoms::BumpPeakNodes.call(kingdom_id: new_owner_id)
      instrument_captured(kingdom_id: new_owner_id, battle: battle)
    end

    def instrument_captured(kingdom_id:, battle:)
      ActiveSupport::Notifications.instrument(
        "dun.node.captured",
        world_id: @node.region.world_id,
        region_id: @node.region_id,
        node_id: @node.id,
        kingdom_id: kingdom_id,
        battle_id: battle&.id
      )
    end
  end
end
