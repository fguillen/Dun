module Api
  class KingdomsController < Api::BaseController
    def show
      kingdom = load_kingdom
      Buildings::ResolveCompletions.call(kingdom)
      kingdom.reload
      render json: self.class.serialize(kingdom)
    end

    def build
      kingdom = load_kingdom
      kind = params.require(:building).to_s
      target_level = params.require(:target_level).to_i

      order = Buildings::Queue.call(kingdom: kingdom, kind: kind, target_level: target_level)
      render json: self.class.serialize_build_order(order), status: :created
    rescue Buildings::Queue::UnknownBuilding => e
      render_error(code: "unknown_building", message: e.message, status: :unprocessable_entity)
    rescue Buildings::Queue::WorldNotBuildable => e
      render_error(code: "world_not_buildable", message: e.message, status: :unprocessable_entity)
    rescue Buildings::Queue::KingdomEliminated => e
      render_error(code: "kingdom_eliminated", message: e.message, status: :unprocessable_entity)
    rescue Buildings::Queue::InvalidTargetLevel => e
      render_error(code: "invalid_target_level", message: e.message, status: :unprocessable_entity)
    rescue Buildings::Queue::TierGateUnmet => e
      render_error(code: "tier_gate_unmet", message: e.message, status: :unprocessable_entity)
    rescue Buildings::Queue::QueueFull => e
      render_error(code: "queue_full", message: e.message, status: :unprocessable_entity)
    rescue Stockpile::Apply::InsufficientResources => e
      render_error(code: "insufficient_resources", message: e.message, status: :unprocessable_entity)
    end

    def self.serialize(kingdom)
      stockpile = Stockpile::Read.call(kingdom)
      warehouse_level = kingdom.buildings.where(kind: "warehouse").pick(:level).to_i
      cap = Buildings::Catalog.warehouse_cap(warehouse_level)
      production = Kingdom::RESOURCES.each_with_object({}) do |resource, out|
        out[resource] = Production::RateFor.call(kingdom: kingdom, resource: resource)
      end

      {
        id: kingdom.id,
        world_id: kingdom.world_id,
        home_region_id: kingdom.home_region_id,
        stockpiles: stockpile,
        warehouse_cap: cap,
        production_rates: production,
        joined_at: kingdom.joined_at&.iso8601,
        eliminated_at: kingdom.eliminated_at&.iso8601,
        buildings: kingdom.buildings.order(:kind).map { |b| serialize_building(b) },
        in_progress_builds: kingdom.build_orders.in_progress.order(:completes_at).map { |o| serialize_build_order(o) }
      }
    end

    def self.serialize_building(building)
      { id: building.id, kind: building.kind, level: building.level }
    end

    def self.serialize_build_order(order)
      {
        id: order.id,
        building_id: order.building_id,
        kind: order.building.kind,
        target_level: order.target_level,
        started_at: order.started_at&.iso8601,
        completes_at: order.completes_at&.iso8601,
        completed_at: order.completed_at&.iso8601,
        cancelled_at: order.cancelled_at&.iso8601
      }
    end

    private

    def load_kingdom
      kingdom = Kingdom.find(params[:id])
      profile = PlayerProfile.find_by(server_id: kingdom.world.server_id, player_id: Current.player.id)
      raise ActiveRecord::RecordNotFound, "kingdom not visible" if profile.nil?
      raise ActiveRecord::RecordNotFound, "kingdom not visible" if kingdom.player_profile_id != profile.id

      kingdom
    end
  end
end
