class Region < ApplicationRecord
  TERRAINS = %w[plains forest hills mountain marsh].freeze
  TERRAIN_MARCH_MOD = { "plains" => 1.0, "forest" => 0.8, "hills" => 0.9, "mountain" => 0.6, "marsh" => 0.5 }.freeze
  # §16.10 — additive Def multiplier granted to defender on this terrain.
  TERRAIN_COMBAT_MOD = { "plains" => 0.0, "forest" => 0.10, "hills" => 0.15, "mountain" => 0.25, "marsh" => 0.0 }.freeze
  # §16.10 — additive Atk multiplier penalty applied to attacker fighting in a marsh.
  MARSH_ATTACKER_PENALTY = -0.10
  TERRAIN_COMBAT_CAP = 0.25
  SPAWN_TERRAINS = %w[plains hills].freeze

  belongs_to :world
  has_many :nodes, dependent: :destroy
  has_one  :ruin, dependent: :destroy

  has_many :adjacencies_as_a, class_name: "RegionAdjacency", foreign_key: :region_a_id, dependent: :destroy, inverse_of: :region_a
  has_many :adjacencies_as_b, class_name: "RegionAdjacency", foreign_key: :region_b_id, dependent: :destroy, inverse_of: :region_b

  validates :name, presence: true, uniqueness: { scope: :world_id }
  validates :terrain, inclusion: { in: TERRAINS }

  # Derived region ownership (no owner column on regions). A region with a
  # home-hoard node is owned by that node's owner — preserving home-region
  # semantics, including nil while the hoard is still wilderness. Otherwise the
  # region follows its captured node(s): the sole owner across owned nodes, or
  # nil when none are owned or they disagree (contested).
  def owner_kingdom_id
    hoard = nodes.find(&:is_home_hoard)
    return hoard.owner_kingdom_id if hoard

    owners = nodes.filter_map(&:owner_kingdom_id).uniq
    owners.first if owners.one?
  end

  def adjacent_regions
    Region
      .where(id: adjacencies_as_a.select(:region_b_id))
      .or(Region.where(id: adjacencies_as_b.select(:region_a_id)))
  end

  def adjacent_to?(other)
    other_id = other.is_a?(Region) ? other.id : other
    RegionAdjacency.adjacent?(id, other_id)
  end

  def x
    position["x"]
  end

  def y
    position["y"]
  end
end
