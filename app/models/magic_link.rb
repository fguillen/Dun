class MagicLink < ApplicationRecord
  EXPIRY = 15.minutes
  OWNER_TYPES = %w[Player Admin].freeze

  belongs_to :owner, polymorphic: true, optional: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :owner_type, inclusion: { in: OWNER_TYPES }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  class Expired < StandardError; end
  class AlreadyConsumed < StandardError; end
  class InvalidToken < StandardError; end

  def self.generate_for(owner_type:, email:)
    raise ArgumentError, "owner_type must be Player or Admin" unless OWNER_TYPES.include?(owner_type)

    raw_token = SecureRandom.urlsafe_base64(32)
    record = create!(
      owner_type: owner_type,
      email: email,
      token_digest: digest(raw_token),
      expires_at: EXPIRY.from_now
    )
    [ record, raw_token ]
  end

  def self.find_by_token(raw_token)
    return nil if raw_token.blank?

    find_by(token_digest: digest(raw_token))
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def consume!(owner:)
    raise AlreadyConsumed if consumed_at.present?
    raise Expired if expires_at < Time.current
    raise ArgumentError, "owner type mismatch" unless owner.class.name == owner_type

    update!(owner: owner, consumed_at: Time.current)
  end
end
