class PlayerProfile < ApplicationRecord
  HANDLE_FORMAT = /\A[A-Za-z][A-Za-z0-9_]*(?: [A-Za-z0-9_]+)*\z/
  HANDLE_LENGTH = (3..20).freeze
  REAL_NAME_LENGTH = (1..60).freeze
  RESERVED_HANDLES = %w[admin system dun world neutral wilderness server anonymous none null].freeze

  belongs_to :server
  belongs_to :player

  validates :player_id, uniqueness: { scope: :server_id }
  validates :handle,
            length: { in: HANDLE_LENGTH, allow_nil: true },
            format: { with: HANDLE_FORMAT, allow_nil: true, message: "must start with a letter; letters, digits, underscore, and single internal spaces only" },
            uniqueness: { scope: :server_id, case_sensitive: false, allow_nil: true }
  validate :handle_not_reserved
  validates :real_name, length: { in: REAL_NAME_LENGTH, allow_nil: true }

  # Phase 2 will activate this: a profile is locked from handle changes while
  # its kingdom is part of any active round (§17.1). Until then it returns
  # false so the wiring is in place but the constraint is inert.
  def locked?
    false
  end

  private

  def handle_not_reserved
    return if handle.blank?
    errors.add(:handle, "is reserved") if RESERVED_HANDLES.include?(handle.downcase)
  end
end
