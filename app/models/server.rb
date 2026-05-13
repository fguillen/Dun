class Server < ApplicationRecord
  belongs_to :owner, class_name: "Admin", foreign_key: :owner_admin_id

  has_many :server_adminships, dependent: :destroy
  has_many :admins, through: :server_adminships
  has_many :server_accesses, dependent: :destroy
  has_many :server_memberships, dependent: :destroy
  has_many :players, through: :server_memberships

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase }

  validates :slug, presence: true, uniqueness: { case_sensitive: false }, format: { with: /\A[a-z0-9][a-z0-9-]{1,38}[a-z0-9]\z/, message: "must be 3-40 chars, lowercase alnum + hyphens" }
  validates :name, presence: true
  validates :max_concurrent_worlds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_worlds_per_account, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def admits?(email)
    ServerAccess.admits?(self, email)
  end
end
