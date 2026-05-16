module Titles
  # Returns the inline title string for a player profile, or nil if the
  # profile has no titles. Per §17.4: pick the most recent title's world;
  # append "×N" if the same world's title has been awarded N>1 times.
  class Render
    def self.call(player_profile)
      new(player_profile).call
    end

    def initialize(player_profile)
      @player_profile = player_profile
    end

    def call
      latest = PlayerTitle
        .where(player_profile_id: @player_profile.id, kind: PlayerTitle::CHAMPION)
        .order(awarded_at: :desc)
        .includes(:world)
        .first
      return nil if latest.nil?

      world = latest.world
      count_for_world = PlayerTitle
        .joins(:world)
        .where(player_profile_id: @player_profile.id, kind: PlayerTitle::CHAMPION, worlds: { name: world.name })
        .count

      base = "[Champion of #{world.name}"
      base += " ×#{count_for_world}" if count_for_world > 1
      base += "]"
      base
    end
  end
end
