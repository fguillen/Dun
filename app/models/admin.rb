class Admin < ApplicationRecord
  has_many :api_keys, as: :owner, dependent: :destroy
  has_many :magic_links, as: :owner, dependent: :nullify
  has_many :server_adminships, dependent: :destroy
  has_many :administered_servers, through: :server_adminships, source: :server
  has_many :owned_servers, class_name: "Server", foreign_key: :owner_admin_id, dependent: :nullify

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
end
