class PlayerTitle < ApplicationRecord
  CHAMPION = "champion".freeze

  belongs_to :player_profile
  belongs_to :world

  validates :kind, presence: true
  validates :awarded_at, presence: true
end
