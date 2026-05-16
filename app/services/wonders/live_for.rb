module Wonders
  # Returns the live (foundation|construction|consecration) Wonder for a
  # kingdom, or nil. Used by build queue lock and combat damage path.
  class LiveFor
    def self.call(kingdom)
      Wonder.where(kingdom_id: kingdom.id, status: Wonder::LIVE_STATUSES).first
    end
  end
end
