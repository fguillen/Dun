module Ruins
  # Ruin claim flow: attacker fights the ruin's one-time NPC garrison and on
  # victory transfers the ruin's resource cache to its kingdom's stockpile.
  # The cache is applied via `Stockpile::Apply`, which silently caps at the
  # warehouse limit — excess is lost per §16.11. The ruin row is preserved
  # (claimed_by + claimed_at) so the world ledger keeps the record.
  class Claim
    class AlreadyClaimed < StandardError; end

    ATTACKER_WIN = Combat::ApplyOutcome::ATTACKER_WIN

    def self.call(march_order:, ruin:, rng: Random.new)
      new(march_order: march_order, ruin: ruin, rng: rng).call
    end

    def initialize(march_order:, ruin:, rng:)
      @march_order = march_order
      @ruin = ruin
      @rng = rng
    end

    def call
      raise AlreadyClaimed, "ruin #{@ruin.id} already claimed" if @ruin.claimed?

      battle = Combat::ResolveGarrison.call(march_order: @march_order, garrison: @ruin.garrison, rng: @rng)
      return nil if battle.nil?

      return battle unless ATTACKER_WIN.include?(battle.outcome)

      kingdom = Kingdom.find(battle.attacker_kingdom_id)
      granted = apply_cache(kingdom)
      battle.update!(loot: granted)

      @ruin.update!(claimed_by_kingdom_id: kingdom.id, claimed_at: Time.current)

      ActiveSupport::Notifications.instrument(
        "dun.ruin.claimed",
        world_id: battle.world_id,
        region_id: battle.region_id,
        ruin_id: @ruin.id,
        kingdom_id: kingdom.id,
        battle_id: battle.id,
        granted: granted
      )

      battle
    end

    private

    def apply_cache(kingdom)
      cache = @ruin.cache.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_i }
      return {} if cache.values.all?(&:zero?)

      before = Stockpile::Read.call(kingdom)
      Stockpile::Apply.call(kingdom: kingdom, deltas: cache)
      after = Stockpile::Read.call(kingdom.reload)

      Kingdom::RESOURCES.each_with_object({}) do |resource, out|
        out[resource] = (after[resource].to_i - before[resource].to_i)
      end
    end
  end
end
