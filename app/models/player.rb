class Player < ApplicationRecord
  has_many :api_keys, as: :owner, dependent: :destroy
  has_many :magic_links, as: :owner, dependent: :nullify
  has_many :server_memberships, dependent: :destroy
  has_many :servers, through: :server_memberships

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
end
