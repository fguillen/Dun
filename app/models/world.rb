class World < ApplicationRecord
  STATUSES = %w[proposed grace active archived cancelled].freeze
  LIVE_STATUSES = %w[proposed grace active].freeze

  belongs_to :server

  has_many :world_invitations, dependent: :destroy
  has_many :regions, dependent: :destroy
  has_many :nodes, through: :regions
  has_many :ruins, through: :regions
  has_many :kingdoms, dependent: :destroy
  belongs_to :winner_kingdom, class_name: "Kingdom", optional: true
  has_one :round_archive, dependent: :destroy

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase }

  validates :name, presence: true
  validates :slug, presence: true,
                   uniqueness: { scope: :server_id, case_sensitive: false },
                   format: { with: /\A[a-z0-9][a-z0-9-]{1,38}[a-z0-9]\z/, message: "must be 3-40 chars, lowercase alnum + hyphens" }
  validates :seed, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :min_players, numericality: { only_integer: true, greater_than: 0 }
  validates :auto_cancel_after_hours, numericality: { only_integer: true, greater_than: 0 }
  validates :t0_at, presence: true

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def joinable?
    proposed? || grace?
  end

  def live?
    LIVE_STATUSES.include?(status)
  end

  def seed_int
    seed.to_i(16)
  end
end
