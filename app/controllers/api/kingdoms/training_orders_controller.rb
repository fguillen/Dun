module Api
  module Kingdoms
    class TrainingOrdersController < Api::BaseController
      def create
        kingdom = load_kingdom
        building_kind = params.require(:building).to_s
        unit = params.require(:unit).to_s
        count = params.require(:count).to_i

        order = Training::Queue.call(
          kingdom: kingdom, building_kind: building_kind, unit: unit, count: count
        )
        render json: self.class.serialize(order), status: :created
      rescue Training::Queue::UnknownUnit => e
        render_error(code: "unknown_unit", message: e.message, status: :unprocessable_entity)
      rescue Training::Queue::BuildingMissing => e
        render_error(code: "building_missing", message: e.message, status: :unprocessable_entity)
      rescue Training::Queue::UnitNotTrainableHere => e
        render_error(code: "unit_not_trainable_here", message: e.message, status: :unprocessable_entity)
      rescue Training::Queue::WorldNotBuildable => e
        render_error(code: "world_not_buildable", message: e.message, status: :unprocessable_entity)
      rescue Training::Queue::KingdomEliminated => e
        render_error(code: "kingdom_eliminated", message: e.message, status: :unprocessable_entity)
      rescue Stockpile::Apply::InsufficientResources => e
        render_error(code: "insufficient_resources", message: e.message, status: :unprocessable_entity)
      end

      def destroy
        kingdom = load_kingdom
        order = kingdom.training_orders.find(params[:id])

        Training::Cancel.call(training_order: order)
        render json: self.class.serialize(order.reload)
      rescue Training::Cancel::AlreadyResolved => e
        render_error(code: "training_order_already_resolved", message: e.message, status: :unprocessable_entity)
      end

      def preview
        kingdom = load_kingdom
        building_kind = params.require(:building).to_s
        unit = params.require(:unit).to_s
        count = params.require(:count).to_i

        Training::ResolveCompletions.call(kingdom)
        kingdom.reload

        render json: Training::Preview.call(
          kingdom: kingdom, building_kind: building_kind, unit: unit, count: count
        )
      rescue Training::Preview::UnknownUnit => e
        render_error(code: "unknown_unit", message: e.message, status: :unprocessable_entity)
      rescue Training::Preview::InvalidBuildingKind => e
        render_error(code: "invalid_building_kind", message: e.message, status: :unprocessable_entity)
      rescue Training::Preview::InvalidCount => e
        render_error(code: "invalid_count", message: e.message, status: :unprocessable_entity)
      end

      def catalog
        kingdom = load_kingdom

        Training::ResolveCompletions.call(kingdom)
        kingdom.reload

        render json: Training::Catalog.call(
          kingdom: kingdom, building_kind: params[:building].presence
        )
      rescue Training::Catalog::InvalidBuildingKind => e
        render_error(code: "invalid_building_kind", message: e.message, status: :unprocessable_entity)
      end

      def self.serialize(order)
        {
          id: order.id,
          kingdom_id: order.kingdom_id,
          building_id: order.building_id,
          building_kind: order.building_kind,
          unit: order.unit,
          count: order.count,
          started_at: order.started_at&.iso8601,
          completes_at: order.completes_at&.iso8601,
          completed_at: order.completed_at&.iso8601,
          cancelled_at: order.cancelled_at&.iso8601
        }
      end

      private

      def load_kingdom
        kingdom = Kingdom.find(params[:kingdom_id])
        profile = PlayerProfile.find_by(server_id: kingdom.world.server_id, player_id: Current.player.id)
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if profile.nil?
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if kingdom.player_profile_id != profile.id

        kingdom
      end
    end
  end
end
