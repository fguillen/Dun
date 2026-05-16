class LeaderboardSnapshot < ApplicationRecord
  KINDS = %w[champions wreckers warlords veterans].freeze

  belongs_to :server

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :snapshot_at, presence: true
  # Uniqueness is enforced by the unique DB index on (server_id, kind);
  # we deliberately skip the AR-level validation so callers can rely on
  # ActiveRecord::RecordNotUnique for race detection.
end
