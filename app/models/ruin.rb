class Ruin < ApplicationRecord
  TIERS = %w[minor standard major].freeze

  GARRISONS = {
    "minor"    => { levy: 20, archer: 10 },
    "standard" => { levy: 40, archer: 20, pikeman: 10 },
    "major"    => { levy: 60, archer: 30, pikeman: 20, knight: 10 }
  }.freeze

  CACHES = {
    "minor"    => { gold: 4_000,  wood: 4_000,  stone: 2_000,  iron: 4_000 },
    "standard" => { gold: 10_000, wood: 10_000, stone: 6_000,  iron: 10_000 },
    "major"    => { gold: 25_000, wood: 25_000, stone: 15_000, iron: 25_000 }
  }.freeze

  belongs_to :region
  has_one :world, through: :region

  validates :tier, inclusion: { in: TIERS }

  scope :unclaimed, -> { where(claimed_by_kingdom_id: nil) }
  scope :claimed, -> { where.not(claimed_by_kingdom_id: nil) }

  def claimed?
    claimed_by_kingdom_id.present?
  end
end
