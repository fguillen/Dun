class PlayerProfileStats < ApplicationRecord
  self.table_name = "player_profile_stats"

  COUNTER_COLUMNS = %i[
    rounds_played
    rounds_won
    wonders_completed
    wonders_destroyed
    peak_nodes
    raids_launched
    raids_defended
    raids_won_offense
    raids_won_defense
    resources_looted
  ].freeze

  belongs_to :player_profile

  def to_counters
    COUNTER_COLUMNS.each_with_object({}) do |column, h|
      h[column] = public_send(column).to_i
    end
  end
end
