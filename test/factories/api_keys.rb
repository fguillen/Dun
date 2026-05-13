FactoryBot.define do
  factory :api_key do
    association :owner, factory: :player
    token_digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }
    expires_at { 90.days.from_now }
  end
end
