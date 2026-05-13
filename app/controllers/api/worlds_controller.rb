module Api
  class WorldsController < Api::BaseController
    def show
      world = world_visible_to_player
      render json: self.class.serialize(world, kingdom_for(world))
    end

    def join
      world = world_visible_to_player
      kingdom = ::Worlds::Join.call(world: world, player: Current.player)
      render json: self.class.serialize_kingdom(kingdom), status: :created
    rescue ::Worlds::Join::WorldNotJoinable => e
      render_error(code: "world_not_joinable", message: e.message, status: :unprocessable_entity)
    rescue ::Worlds::Join::ServerAccessDenied, ::Worlds::Join::NotServerMember => e
      render_error(code: "forbidden", message: e.message, status: :forbidden)
    rescue ::Worlds::Join::WorldAccountLimitReached => e
      render_error(code: "world_account_limit_reached", message: e.message, status: :unprocessable_entity)
    rescue ::MapGeneration::AssignLateJoiner::NoSpawnSlotAvailable => e
      render_error(code: "no_spawn_slot", message: e.message, status: :unprocessable_entity)
    end

    def self.serialize(world, kingdom = nil)
      payload = {
        id: world.id,
        server_id: world.server_id,
        name: world.name,
        slug: world.slug,
        status: world.status,
        min_players: world.min_players,
        t0_at: world.t0_at&.iso8601,
        grace_closes_at: world.grace_closes_at&.iso8601,
        region_count: world.regions.count,
        kingdom_count: world.kingdoms.count
      }
      payload[:my_kingdom] = serialize_kingdom(kingdom) if kingdom
      payload
    end

    def self.serialize_kingdom(kingdom)
      {
        id: kingdom.id,
        world_id: kingdom.world_id,
        home_region_id: kingdom.home_region_id,
        stockpiles: kingdom.stockpiles,
        joined_at: kingdom.joined_at&.iso8601
      }
    end

    private

    def world_visible_to_player
      world = World.find(params[:id])
      unless world.server.server_memberships.exists?(player_id: Current.player.id)
        raise ActiveRecord::RecordNotFound, "world not visible"
      end
      world
    end

    def kingdom_for(world)
      profile = PlayerProfile.find_by(server: world.server, player: Current.player)
      return nil if profile.nil?

      world.kingdoms.find_by(player_profile_id: profile.id)
    end
  end
end
