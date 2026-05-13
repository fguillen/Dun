class ApiKey < ApplicationRecord
  LIFETIME = 90.days
  OWNER_TYPES = %w[Player Admin].freeze

  belongs_to :owner, polymorphic: true

  validates :owner_type, inclusion: { in: OWNER_TYPES }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.generate_for(owner:, name: nil)
    raise ArgumentError, "owner must be Player or Admin" unless OWNER_TYPES.include?(owner.class.name)

    raw_token = SecureRandom.urlsafe_base64(32)
    record = create!(
      owner: owner,
      name: name,
      token_digest: digest(raw_token),
      expires_at: LIFETIME.from_now
    )
    [ record, raw_token ]
  end

  # Returns [api_key, owner] or nil. Slides expires_at forward and refreshes
  # last_used_at on a successful authentication so the 90-day window is rolling.
  def self.authenticate(raw_token, owner_type:)
    return nil if raw_token.blank?
    raise ArgumentError, "owner_type must be Player or Admin" unless OWNER_TYPES.include?(owner_type)

    key = active.where(owner_type: owner_type).find_by(token_digest: digest(raw_token))
    return nil unless key

    key.touch_last_used!
    [ key, key.owner ]
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def touch_last_used!
    now = Time.current
    update_columns(last_used_at: now, expires_at: LIFETIME.from_now)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil? && expires_at > Time.current
  end
end
