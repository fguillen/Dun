module Rounds
  # Builds the JSONB frozen_state blob for a round archive. Pure projection —
  # reads current world state and returns a hash. Per §16.6: final map state,
  # final resource standings, Wonder HP at win moment, battle/caravan/node
  # counts.
  class SnapshotState
    def self.call(world, ended_at: Time.current)
      new(world, ended_at: ended_at).call
    end

    def initialize(world, ended_at:)
      @world = world
      @ended_at = ended_at
    end

    def call
      {
        "ended_at" => @ended_at.iso8601,
        "regions" => regions_payload,
        "kingdoms" => kingdoms_payload,
        "wonder" => wonder_payload,
        "battles_count" => Battle.where(world_id: @world.id).count,
        "caravans_count" => Caravan.where(world_id: @world.id).count,
        "nodes_count" => Node.joins(:region).where(regions: { world_id: @world.id }).count
      }
    end

    private

    def regions_payload
      @world.regions.includes(:nodes).order(:name).map do |region|
        {
          "id" => region.id,
          "name" => region.name,
          "terrain" => region.terrain,
          "position" => region.position,
          "is_hub" => region.is_hub,
          "node_ids" => region.nodes.map(&:id)
        }
      end
    end

    def kingdoms_payload
      @world.kingdoms.includes(:player_profile, :buildings, :owned_nodes).order(:joined_at).map do |kingdom|
        building_levels = kingdom.buildings.each_with_object({}) { |b, h| h[b.kind] = b.level }
        {
          "id" => kingdom.id,
          "handle" => kingdom.player_profile.handle,
          "real_name" => kingdom.player_profile.real_name,
          "home_region_id" => kingdom.home_region_id,
          "final_stockpiles" => Stockpile::Read.call(kingdom),
          "building_levels" => building_levels,
          "peak_nodes" => kingdom.peak_nodes,
          "final_node_count" => kingdom.owned_nodes.count,
          "joined_at" => kingdom.joined_at&.iso8601,
          "eliminated_at" => kingdom.eliminated_at&.iso8601
        }
      end
    end

    def wonder_payload
      wonder = Wonder.joins(:kingdom).where(kingdoms: { world_id: @world.id }).order(updated_at: :desc).first
      return nil if wonder.nil?
      {
        "kingdom_id" => wonder.kingdom_id,
        "name" => wonder.name,
        "status" => wonder.status,
        "hp" => wonder.hp,
        "target_hp" => wonder.target_hp,
        "damage_events_count" => WonderDamageEvent.where(wonder_id: wonder.id).count,
        "started_at" => wonder.started_at&.iso8601,
        "completed_at" => wonder.completed_at&.iso8601,
        "destroyed_at" => wonder.destroyed_at&.iso8601
      }
    end
  end
end
