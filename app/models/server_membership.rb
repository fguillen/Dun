class ServerMembership < ApplicationRecord
  belongs_to :server
  belongs_to :player

  validates :player_id, uniqueness: { scope: :server_id }

  before_validation :set_joined_at

  private

  def set_joined_at
    self.joined_at ||= Time.current
  end
end
