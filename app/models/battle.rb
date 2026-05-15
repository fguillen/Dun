class Battle < ApplicationRecord
  include HasUlid

  OUTCOMES = %w[attacker_victory defender_victory attacker_rout defender_rout].freeze

  belongs_to :world
  belongs_to :region
  belongs_to :attacker_kingdom, class_name: "Kingdom"
  belongs_to :defender_kingdom, class_name: "Kingdom"
  belongs_to :march_order, optional: true
  has_many :participants, class_name: "BattleParticipant", dependent: :destroy

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :started_at, :ended_at, presence: true

  scope :involving, ->(kingdom_id) {
    where("attacker_kingdom_id = :id OR defender_kingdom_id = :id", id: kingdom_id)
  }
end
