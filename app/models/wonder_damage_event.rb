class WonderDamageEvent < ApplicationRecord
  include HasUlid

  belongs_to :wonder
  belongs_to :attacker_kingdom, class_name: "Kingdom"
  belongs_to :battle, optional: true

  validates :trebuchets_surviving, :hp_before, :hp_after, :occurred_at, presence: true
end
