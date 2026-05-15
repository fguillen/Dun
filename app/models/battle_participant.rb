class BattleParticipant < ApplicationRecord
  include HasUlid

  SIDES = %w[attacker defender].freeze

  belongs_to :battle
  belongs_to :kingdom
  belongs_to :army, optional: true

  validates :side, inclusion: { in: SIDES }
end
