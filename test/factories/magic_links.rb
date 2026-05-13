FactoryBot.define do
  factory :magic_link do
    sequence(:email) { |n| "user#{n}@example.com" }
    owner_type { "Player" }
    token_digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }
    expires_at { 15.minutes.from_now }
  end
end
