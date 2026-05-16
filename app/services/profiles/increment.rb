module Profiles
  # Atomically increment counter columns on a player's PlayerProfileStats row.
  # Uses a single UPDATE with SQL arithmetic so concurrent increments compose
  # correctly without row-level locking.
  class Increment
    class UnknownColumn < ArgumentError; end

    ALLOWED = PlayerProfileStats::COUNTER_COLUMNS.map(&:to_s).to_set.freeze

    def self.call(player_profile:, deltas:)
      new(player_profile: player_profile, deltas: deltas).call
    end

    def initialize(player_profile:, deltas:)
      @player_profile = player_profile
      @deltas = deltas
    end

    def call
      return if @deltas.blank?
      pairs = @deltas.map do |column, value|
        column_s = column.to_s
        raise UnknownColumn, "unknown stats column #{column_s.inspect}" unless ALLOWED.include?(column_s)
        amount = value.to_i
        next nil if amount.zero?
        "#{column_s} = #{column_s} + #{amount}"
      end.compact

      return if pairs.empty?

      ensure_row
      PlayerProfileStats
        .where(player_profile_id: @player_profile.id)
        .update_all(pairs.join(", "))
    end

    private

    def ensure_row
      return if PlayerProfileStats.exists?(player_profile_id: @player_profile.id)
      PlayerProfileStats.create!(player_profile_id: @player_profile.id)
    rescue ActiveRecord::RecordNotUnique
      # another process beat us to it; safe to ignore
    end
  end
end
