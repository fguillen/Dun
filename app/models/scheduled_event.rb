class ScheduledEvent < ApplicationRecord
  include HasUlid

  KINDS = %w[
    build_completion
    grace_expiry
    training_completion
    march_arrival
    battle_resolution
    wonder_phase
    caravan_arrival
    weather_edge
  ].freeze

  belongs_to :world

  validates :kind, inclusion: { in: KINDS }
  validates :fire_at, presence: true

  scope :pending, -> { where(processed_at: nil) }
  scope :processed, -> { where.not(processed_at: nil) }
  scope :ripe, ->(at = Time.current) { pending.where("fire_at <= ?", at) }

  def pending?
    processed_at.nil?
  end
end
