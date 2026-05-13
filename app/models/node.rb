class Node < ApplicationRecord
  RESOURCES = %w[gold wood stone iron].freeze
  TIERS = %w[poor standard rich].freeze
  TIER_BASE_RATE = { "poor" => 120, "standard" => 250, "rich" => 500 }.freeze

  WILDERNESS_GARRISONS = {
    "poor"     => { levy: 15, archer: 5 },
    "standard" => { levy: 25, archer: 10, pikeman: 5 },
    "rich"     => { levy: 40, archer: 20, pikeman: 15, knight: 5 }
  }.freeze

  belongs_to :region
  has_one :world, through: :region

  validates :resource, inclusion: { in: RESOURCES }
  validates :tier, inclusion: { in: TIERS }
  validates :base_rate, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :unclaimed, -> { where(owner_kingdom_id: nil) }
  scope :claimed, -> { where.not(owner_kingdom_id: nil) }

  def wilderness?
    owner_kingdom_id.nil?
  end
end
