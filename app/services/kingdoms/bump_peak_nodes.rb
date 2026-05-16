module Kingdoms
  # Recomputes the kingdom's owned-node count and folds it into
  # `kingdoms.peak_nodes` via GREATEST. Called after every node ownership
  # change so the per-round peak tracks correctly.
  class BumpPeakNodes
    def self.call(kingdom_id:)
      return if kingdom_id.blank?
      Kingdom
        .where(id: kingdom_id)
        .update_all(<<~SQL.squish)
          peak_nodes = GREATEST(
            peak_nodes,
            (SELECT COUNT(*) FROM nodes WHERE owner_kingdom_id = kingdoms.id)
          )
        SQL
    end
  end
end
