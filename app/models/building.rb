class Building < ApplicationRecord
  include HasUlid

  belongs_to :kingdom
  has_many :build_orders, dependent: :destroy
  has_many :training_orders, dependent: :destroy

  validates :kind, presence: true, inclusion: { in: Buildings::Catalog::KINDS }
  validates :kind, uniqueness: { scope: :kingdom_id }
  validates :level, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: Buildings::Catalog::MAX_LEVEL
  }
end
