class Player < ApplicationRecord
  has_many :api_keys, as: :owner, dependent: :destroy
  has_many :magic_links, as: :owner, dependent: :nullify

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
end
