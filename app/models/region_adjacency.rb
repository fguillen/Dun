class RegionAdjacency < ApplicationRecord
  belongs_to :region_a, class_name: "Region"
  belongs_to :region_b, class_name: "Region"

  validates :region_a_id, presence: true
  validates :region_b_id, presence: true,
                          uniqueness: { scope: :region_a_id }
  validate :endpoints_distinct
  validate :ordered_endpoints
  validate :same_world

  def self.connect(a, b)
    a_id, b_id = [ a.is_a?(Region) ? a.id : a, b.is_a?(Region) ? b.id : b ].sort
    find_or_create_by!(region_a_id: a_id, region_b_id: b_id)
  end

  def self.adjacent?(a_id, b_id)
    lo, hi = [ a_id, b_id ].sort
    exists?(region_a_id: lo, region_b_id: hi)
  end

  private

  def endpoints_distinct
    errors.add(:region_b_id, "must differ from region_a_id") if region_a_id == region_b_id
  end

  def ordered_endpoints
    return if region_a_id.nil? || region_b_id.nil?

    errors.add(:region_a_id, "must be less than region_b_id (canonical ordering)") if region_a_id > region_b_id
  end

  def same_world
    return if region_a.nil? || region_b.nil?

    errors.add(:base, "endpoints must share a world") if region_a.world_id != region_b.world_id
  end
end
