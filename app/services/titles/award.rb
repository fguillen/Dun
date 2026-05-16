module Titles
  class Award
    def self.call(player_profile:, world:, kind: PlayerTitle::CHAMPION, at: Time.current)
      new(player_profile: player_profile, world: world, kind: kind, at: at).call
    end

    def initialize(player_profile:, world:, kind:, at:)
      @player_profile = player_profile
      @world = world
      @kind = kind
      @at = at
    end

    def call
      PlayerTitle.find_or_create_by!(
        player_profile_id: @player_profile.id,
        world_id: @world.id,
        kind: @kind
      ) do |title|
        title.awarded_at = @at
      end
    rescue ActiveRecord::RecordNotUnique
      PlayerTitle.find_by!(
        player_profile_id: @player_profile.id,
        world_id: @world.id,
        kind: @kind
      )
    end
  end
end
