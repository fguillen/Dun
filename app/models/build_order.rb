class BuildOrder < ApplicationRecord
  include HasUlid

  belongs_to :kingdom
  belongs_to :building

  validates :target_level, numericality: {
    only_integer: true,
    greater_than: 0,
    less_than_or_equal_to: Buildings::Catalog::MAX_LEVEL
  }
  validates :started_at, :completes_at, presence: true

  scope :in_progress, -> { where(cancelled_at: nil, completed_at: nil) }
  scope :ripe, ->(at = Time.current) { in_progress.where("completes_at <= ?", at) }

  def in_progress?
    cancelled_at.nil? && completed_at.nil?
  end

  def resolved?
    !in_progress?
  end
end
