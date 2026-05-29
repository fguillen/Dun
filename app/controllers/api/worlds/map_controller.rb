module Api
  module Worlds
    class MapController < Api::BaseController
      def index
        regions = world.regions.includes(:nodes, :ruin).order(:name)
        adjacency = build_adjacency(regions)
        my_spawn_id = my_kingdoms_spawn_id
        handle_map = Kingdom.handles_for(regions.map { |r| region_owner_id(r) })
        armies_by_region = armies_by_region(regions)

        render json: {
          regions: regions.map { |r| serialize(r, adjacency, my_spawn_id, handle_map, armies_by_region) }
        }
      end

      private

      def world
        @world ||= begin
          w = World.find(params[:world_id])
          raise ActiveRecord::RecordNotFound, "world not visible" unless w.server.server_memberships.exists?(player_id: Current.player.id)
          w
        end
      end

      def build_adjacency(regions)
        ids = regions.map(&:id)
        map = ids.each_with_object({}) { |id, h| h[id] = [] }
        RegionAdjacency.where(region_a_id: ids).pluck(:region_a_id, :region_b_id).each do |a, b|
          map[a] << b
          map[b] << a
        end
        map
      end

      def profile
        return @profile if defined?(@profile)

        @profile = PlayerProfile.find_by(server: world.server, player: Current.player)
      end

      def my_kingdoms_spawn_id
        return nil unless profile

        world.kingdoms.where(player_profile_id: profile.id).pick(:home_region_id)
      end

      # Kingdom ids on this world belonging to the caller — used to flag own armies.
      def my_kingdom_ids
        @my_kingdom_ids ||= profile ? world.kingdoms.where(player_profile_id: profile.id).ids : []
      end

      # All armies in the world grouped by the region they currently sit in.
      # v1 is full visibility (§16.9); v1.1 fog will drop/obscure entries here.
      def armies_by_region(regions)
        Army.where(location_region_id: regions.map(&:id))
            .includes(kingdom: :player_profile)
            .group_by(&:location_region_id)
      end

      # A region's owner is the kingdom holding its home-hoard node (same
      # derivation as RegionsController#serialize).
      def region_owner_id(region)
        region.nodes.find { |n| n.is_home_hoard }&.owner_kingdom_id
      end

      def serialize(region, adjacency, my_spawn_id, handle_map, armies_by_region)
        owner_id = region_owner_id(region)
        {
          id: region.id,
          name: region.name,
          terrain: region.terrain,
          position: region.position,
          is_hub: region.is_hub,
          spawn_eligible: region.spawn_eligible,
          your_spawn: region.id == my_spawn_id,
          owner_kingdom_id: owner_id,
          owner_handle: owner_id && handle_map[owner_id],
          adjacency: adjacency[region.id].sort,
          nodes: region.nodes.map { |n| { id: n.id, resource: n.resource, tier: n.tier, is_home_hoard: n.is_home_hoard } },
          ruin: region.ruin && { id: region.ruin.id, tier: region.ruin.tier, claimed: region.ruin.claimed? },
          visible_armies: (armies_by_region[region.id] || []).map { |a| serialize_army(a) }
        }
      end

      def serialize_army(army)
        {
          army_id: army.id,
          kingdom_id: army.kingdom_id,
          owner_handle: army.kingdom.handle,
          name: army.name,
          mine: my_kingdom_ids.include?(army.kingdom_id),
          status: army.status,
          composition: army.composition
        }
      end
    end
  end
end
