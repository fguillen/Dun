class TradeLedgerEntry < ApplicationRecord
  include HasUlid

  STATUSES = %w[in_transit delivered intercepted].freeze

  belongs_to :world
  belongs_to :caravan

  validates :status, inclusion: { in: STATUSES }
  validates :resource, inclusion: { in: Kingdom::RESOURCES }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :sender_handle_at_send, :receiver_handle_at_send, :recorded_at, presence: true

  scope :for_handle, ->(handle) {
    where(
      "sender_handle_at_send = :h OR receiver_handle_at_send = :h OR attacker_handle = :h",
      h: handle
    )
  }
  scope :since,    ->(time) { where("recorded_at >= ?", time) }
  scope :newest_first, -> { order(recorded_at: :desc, id: :desc) }
end
