class Caravan < ApplicationRecord
  include HasUlid

  STATUSES = %w[in_transit delivered intercepted].freeze

  belongs_to :world
  belongs_to :sender_kingdom,   class_name: "Kingdom"
  belongs_to :receiver_kingdom, class_name: "Kingdom"
  belongs_to :origin_region,      class_name: "Region"
  belongs_to :destination_region, class_name: "Region"
  belongs_to :escort_army,          class_name: "Army",       optional: true
  belongs_to :outbound_march_order, class_name: "MarchOrder", optional: true
  belongs_to :return_march_order,   class_name: "MarchOrder", optional: true
  has_many :ledger_entries, class_name: "TradeLedgerEntry", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :dispatched_at, :arrives_at, presence: true
  validate :payload_well_formed
  validate :escort_units_well_formed

  scope :in_transit,  -> { where(status: "in_transit") }
  scope :delivered,   -> { where(status: "delivered") }
  scope :intercepted, -> { where(status: "intercepted") }

  def in_transit?;  status == "in_transit";  end
  def delivered?;   status == "delivered";   end
  def intercepted?; status == "intercepted"; end

  private

  def payload_well_formed
    unless payload.is_a?(Hash)
      errors.add(:payload, "must be a hash")
      return
    end
    if payload.values.sum(&:to_i) <= 0
      errors.add(:payload, "must include at least one resource amount")
    end
    payload.each do |resource, amount|
      errors.add(:payload, "unknown resource #{resource}") unless Kingdom::RESOURCES.include?(resource.to_s)
      errors.add(:payload, "negative amount for #{resource}") if amount.to_i < 0
    end
  end

  def escort_units_well_formed
    unless escort_units.is_a?(Hash)
      errors.add(:escort_units, "must be a hash")
      return
    end
    if escort_units.values.sum(&:to_i) <= 0
      errors.add(:escort_units, "must include at least one unit")
    end
    escort_units.each do |unit, count|
      errors.add(:escort_units, "unknown unit #{unit}") unless Units::Catalog.kind?(unit.to_s)
      errors.add(:escort_units, "negative count for #{unit}") if count.to_i < 0
    end
  end
end
