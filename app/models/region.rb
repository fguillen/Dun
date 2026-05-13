class Region < ApplicationRecord
  TERRAINS = %w[plains forest hills mountain marsh].freeze
  TERRAIN_MARCH_MOD = { "plains" => 1.0, "forest" => 0.8, "hills" => 0.9, "mountain" => 0.6, "marsh" => 0.5 }.freeze
  SPAWN_TERRAINS = %w[plains hills].freeze

  belongs_to :world
  has_many :nodes, dependent: :destroy
  has_one  :ruin, dependent: :destroy

  has_many :adjacencies_as_a, class_name: "RegionAdjacency", foreign_key: :region_a_id, dependent: :destroy, inverse_of: :region_a
  has_many :adjacencies_as_b, class_name: "RegionAdjacency", foreign_key: :region_b_id, dependent: :destroy, inverse_of: :region_b

  validates :name, presence: true, uniqueness: { scope: :world_id }
  validates :terrain, inclusion: { in: TERRAINS }

  def adjacent_regions
    Region
      .where(id: adjacencies_as_a.select(:region_b_id))
      .or(Region.where(id: adjacencies_as_b.select(:region_a_id)))
  end

  def adjacent_to?(other)
    other_id = other.is_a?(Region) ? other.id : other.to_i
    RegionAdjacency.adjacent?(id, other_id)
  end

  def x
    position["x"]
  end

  def y
    position["y"]
  end
end
