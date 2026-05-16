class Wonder < ApplicationRecord
  include HasUlid

  STATUSES = %w[foundation construction consecration completed destroyed].freeze
  LIVE_STATUSES = %w[foundation construction consecration].freeze
  PHASE_REPAIR_CAP = 2_000
  REPAIR_STONE_PER_HP = 8
  REPAIR_PAUSE_MINUTES_PER_500_HP = 30
  CONSTRUCTION_HP_PER_HOUR = 100
  FOUNDATION_HP = 1_000
  TARGET_HP = 10_000
  MILESTONE_THRESHOLDS = { "25" => 2_500, "50" => 5_000, "75" => 7_500 }.freeze

  belongs_to :kingdom
  has_one :world, through: :kingdom
  has_many :damage_events, class_name: "WonderDamageEvent", dependent: :destroy

  validates :name, inclusion: { in: -> (_) { Wonders::Catalog::NAMES } }
  validates :status, inclusion: { in: STATUSES }
  validates :hp, numericality: { greater_than_or_equal_to: 0 }
  validates :target_hp, numericality: { greater_than: 0 }

  def live?
    LIVE_STATUSES.include?(status)
  end

  def destroyed_status?
    status == "destroyed"
  end

  def completed?
    status == "completed"
  end

  def milestones_paid_for?(percent)
    !!milestones_paid[percent.to_s]
  end
end
