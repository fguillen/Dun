class Army < ApplicationRecord
  include HasUlid

  STATUSES = %w[home marching engaged returning].freeze
  GARRISON_NAME = "Garrison".freeze

  belongs_to :kingdom
  belongs_to :location_region, class_name: "Region"
  has_many :march_orders, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 },
                   uniqueness: { scope: :kingdom_id, case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }
  validate :composition_well_formed

  scope :home,      -> { where(status: "home") }
  scope :marching,  -> { where(status: "marching") }
  scope :engaged,   -> { where(status: "engaged") }
  scope :returning, -> { where(status: "returning") }

  def empty?
    composition.values.map(&:to_i).sum.zero?
  end

  def garrison?
    name == GARRISON_NAME
  end

  def total_capacity
    composition.sum { |unit, count| Units::Catalog.capacity_for(unit) * count.to_i }
  end

  def slowest_speed
    speeds = composition
      .reject { |_, c| c.to_i.zero? }
      .keys
      .map { |u| Units::Catalog.speed_for(u) }
    speeds.min
  end

  def all_terrain_immune?
    units = composition.reject { |_, c| c.to_i.zero? }.keys
    return false if units.empty?
    units.all? { |u| Units::Catalog::TERRAIN_IMMUNE.include?(u) }
  end

  private

  def composition_well_formed
    unless composition.is_a?(Hash)
      errors.add(:composition, "must be a hash")
      return
    end
    composition.each do |unit, count|
      errors.add(:composition, "unknown unit #{unit}") unless Units::Catalog.kind?(unit)
      errors.add(:composition, "negative count for #{unit}") if count.to_i < 0
    end
  end
end
