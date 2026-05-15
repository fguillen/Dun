module Stockpile
  class Checkpoint
    def self.call(kingdom)
      new(kingdom).call
    end

    def initialize(kingdom)
      @kingdom = kingdom
    end

    def call
      kingdom = Stockpile::Apply.call(kingdom: @kingdom, deltas: {})

      ActiveSupport::Notifications.instrument(
        "dun.stockpile.checkpointed",
        world_id: kingdom.world_id,
        kingdom_id: kingdom.id,
        checkpoint_at: kingdom.stockpiles["checkpoint_at"]
      )

      kingdom
    end
  end
end
