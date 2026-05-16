module Profiles
  # Updates a profile's lifetime peak_nodes stat to GREATEST(current, candidate).
  # Used at round end to fold this-round's kingdom peak into the lifetime stat.
  class MaxPeakNodes
    def self.call(player_profile:, candidate:)
      new(player_profile: player_profile, candidate: candidate.to_i).call
    end

    def initialize(player_profile:, candidate:)
      @player_profile = player_profile
      @candidate = candidate
    end

    def call
      return if @candidate <= 0
      PlayerProfileStats
        .where(player_profile_id: @player_profile.id)
        .update_all([ "peak_nodes = GREATEST(peak_nodes, ?)", @candidate ])
    end
  end
end
