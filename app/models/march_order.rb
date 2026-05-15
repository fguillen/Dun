class MarchOrder < ApplicationRecord
  include HasUlid

  INTENTS = %w[attack reinforce scout capture claim_ruin caravan].freeze

  belongs_to :army
  belongs_to :origin_region, class_name: "Region"
  belongs_to :target_region, class_name: "Region"

  validates :intent, inclusion: { in: INTENTS }
  validates :dispatched_at, :arrives_at, presence: true
  validate :path_well_formed

  scope :active, -> { where(arrived_at: nil, recalled_at: nil) }
  scope :ripe, ->(at = Time.current) { active.where("arrives_at <= ?", at) }

  def active?
    arrived_at.nil? && recalled_at.nil?
  end

  def resolved?
    !active?
  end

  private

  def path_well_formed
    unless path.is_a?(Array) && path.all? { |x| x.is_a?(String) }
      errors.add(:path, "must be an array of region IDs")
      return
    end
    errors.add(:path, "is empty") if path.empty?
    errors.add(:path, "first element must equal origin_region_id") if path.first != origin_region_id
    errors.add(:path, "last element must equal target_region_id") if path.last != target_region_id
  end
end
