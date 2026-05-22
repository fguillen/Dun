class Kingdom < ApplicationRecord
  RESOURCES = %w[gold wood stone iron].freeze
  STARTER_STOCKPILE = 500
  LATE_JOINER_BONUS_PER_12H = 1_000
  LATE_JOINER_BONUS_CAP = 4_000

  belongs_to :world
  belongs_to :player_profile
  belongs_to :home_region, class_name: "Region", optional: true

  has_many :owned_nodes, class_name: "Node", foreign_key: :owner_kingdom_id, dependent: :nullify
  has_many :claimed_ruins, class_name: "Ruin", foreign_key: :claimed_by_kingdom_id, dependent: :nullify
  has_many :buildings, dependent: :destroy
  has_many :build_orders, dependent: :destroy
  has_many :armies, dependent: :destroy
  has_many :training_orders, dependent: :destroy

  validates :player_profile_id, uniqueness: { scope: :world_id }
  validate :profile_belongs_to_world_server
  validate :home_region_required_after_proposed

  before_validation :set_joined_at, on: :create

  def stockpile(resource)
    stockpiles[resource.to_s].to_i
  end

  def eliminated?
    eliminated_at.present?
  end

  def stub?
    home_region_id.nil?
  end

  # Player-facing display name; "[unknown]" guards a profile with a nil handle.
  def handle
    player_profile&.handle.presence || "[unknown]"
  end

  # Batch ULID -> handle resolution; avoids N+1 across map / node / roster lists.
  def self.handles_for(kingdom_ids)
    ids = Array(kingdom_ids).compact.uniq
    return {} if ids.empty?

    includes(:player_profile).where(id: ids).each_with_object({}) { |k, h| h[k.id] = k.handle }
  end

  private

  def set_joined_at
    self.joined_at ||= Time.current
  end

  def profile_belongs_to_world_server
    return if player_profile.nil? || world.nil?

    errors.add(:player_profile, "must belong to the world's server") if player_profile.server_id != world.server_id
  end

  def home_region_required_after_proposed
    return if world.nil?
    return if world.proposed?
    return if home_region_id.present?

    errors.add(:home_region_id, "is required once the world has started")
  end
end
