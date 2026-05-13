class ServerAccess < ApplicationRecord
  KINDS = %w[domain invite].freeze

  belongs_to :server

  normalizes :value, with: ->(v) { v.to_s.strip.downcase }

  validates :kind, inclusion: { in: KINDS }
  validates :value, presence: true, uniqueness: { scope: [ :server_id, :kind ], case_sensitive: false }
  validate  :value_shape

  # Returns true if any ServerAccess row on `server` admits `email`. Union
  # semantics per §16.7: domain glob match OR invite email match.
  def self.admits?(server, email)
    normalized = email.to_s.strip.downcase
    return false if normalized.blank?

    where(server: server).any? { |access| access.admits?(normalized) }
  end

  def admits?(normalized_email)
    case kind
    when "domain" then domain_matches?(normalized_email)
    when "invite" then value == normalized_email
    end
  end

  private

  def value_shape
    case kind
    when "domain"
      errors.add(:value, "must include @") unless value.to_s.include?("@")
    when "invite"
      errors.add(:value, "must be an email address") unless URI::MailTo::EMAIL_REGEXP.match?(value)
    end
  end

  def domain_matches?(normalized_email)
    pattern = Regexp.new("\\A" + Regexp.escape(value).gsub("\\*", ".*") + "\\z")
    pattern.match?(normalized_email)
  end
end
