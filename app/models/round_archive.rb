class RoundArchive < ApplicationRecord
  belongs_to :world
  belongs_to :winner_kingdom, class_name: "Kingdom", optional: true

  validates :ended_at, presence: true
end
