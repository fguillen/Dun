class RetiredHandle < ApplicationRecord
  RESERVATION_WINDOW = 30.days

  belongs_to :server

  validates :handle_lower, presence: true
  validates :freed_at, presence: true

  scope :still_reserved, ->(now = Time.current) { where("freed_at > ?", now - RESERVATION_WINDOW) }

  def self.reserved?(server_id:, handle:, now: Time.current)
    return false if handle.blank?
    still_reserved(now)
      .where(server_id: server_id, handle_lower: handle.to_s.downcase)
      .exists?
  end
end
