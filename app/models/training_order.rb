class TrainingOrder < ApplicationRecord
  include HasUlid

  BUILDING_KINDS = %w[barracks stable siege_workshop].freeze

  belongs_to :kingdom
  belongs_to :building

  validates :unit, inclusion: { in: Units::Catalog::KINDS }
  validates :building_kind, inclusion: { in: BUILDING_KINDS }
  validates :count, numericality: { only_integer: true, greater_than: 0 }
  validates :started_at, :completes_at, presence: true
  validate :unit_trainable_at_building

  scope :in_progress, -> { where(cancelled_at: nil, completed_at: nil) }
  scope :ripe, ->(at = Time.current) { in_progress.where("completes_at <= ?", at) }

  def in_progress?
    cancelled_at.nil? && completed_at.nil?
  end

  def resolved?
    !in_progress?
  end

  private

  def unit_trainable_at_building
    return if unit.blank? || building_kind.blank?
    allowed = Units::Catalog::TRAINS_AT[building_kind] || []
    errors.add(:unit, "is not trainable at #{building_kind}") unless allowed.include?(unit)
  end
end
