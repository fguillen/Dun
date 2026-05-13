class ServerAdminship < ApplicationRecord
  ROLES = %w[owner admin].freeze

  belongs_to :server
  belongs_to :admin
  belongs_to :granted_by_admin, class_name: "Admin", optional: true

  validates :role, inclusion: { in: ROLES }
  validates :admin_id, uniqueness: { scope: :server_id }

  before_validation :set_joined_at

  def self.count_admins(server)
    where(server: server).count
  end

  private

  def set_joined_at
    self.joined_at ||= Time.current
  end
end
