class WorldInvitation < ApplicationRecord
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  belongs_to :world
  belongs_to :invited_by_admin, class_name: "Admin"

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true,
                    format: { with: EMAIL_FORMAT },
                    uniqueness: { scope: :world_id, case_sensitive: false }
end
