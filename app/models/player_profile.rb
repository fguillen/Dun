class PlayerProfile < ApplicationRecord
  HANDLE_FORMAT = /\A[A-Za-z0-9_-]{3,24}\z/
  REAL_NAME_LENGTH = (1..60).freeze
  RESERVED_HANDLES = %w[admin system dun world neutral wilderness server anonymous none null].freeze

  belongs_to :server
  belongs_to :player
  has_many :kingdoms, dependent: :destroy
  has_one  :stats, class_name: "PlayerProfileStats", dependent: :destroy
  has_many :titles, class_name: "PlayerTitle", dependent: :destroy

  after_create :create_stats_row

  validates :player_id, uniqueness: { scope: :server_id }
  validates :handle,
            format: { with: HANDLE_FORMAT, allow_nil: true, message: "must be 3–24 characters: letters, digits, underscore, and hyphen only" },
            uniqueness: { scope: :server_id, case_sensitive: false, allow_nil: true }
  validate :handle_not_reserved
  validates :real_name, length: { in: REAL_NAME_LENGTH, allow_nil: true }

  def locked?
    Kingdom
      .where(player_profile_id: id)
      .joins(:world)
      .where(worlds: { status: %w[grace active] })
      .exists?
  end

  private

  def handle_not_reserved
    return if handle.blank?
    errors.add(:handle, "is reserved") if RESERVED_HANDLES.include?(handle.downcase)
  end

  def create_stats_row
    PlayerProfileStats.create!(player_profile_id: id) unless PlayerProfileStats.exists?(player_profile_id: id)
  end
end
