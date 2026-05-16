module Api
  module Kingdoms
    class WondersController < Api::BaseController
      def show
        kingdom = load_owned_kingdom
        wonder = load_wonder(kingdom)
        if wonder.nil?
          render json: { wonder: nil }
          return
        end

        Wonders::ApplyConstruction.call(wonder: wonder) if wonder.status == "construction"
        wonder.reload
        render json: self.class.serialize(wonder)
      end

      def create
        kingdom = load_owned_kingdom
        name = params.require(:name).to_s

        wonder = ::Wonders::Start.call(kingdom: kingdom, name: name)
        render json: self.class.serialize(wonder), status: :created
      rescue ::Wonders::Start::UnknownName => e
        render_error(code: "unknown_wonder_name", message: e.message, status: :unprocessable_entity)
      rescue ::Wonders::Prerequisites::NotMet => e
        render_error(code: "wonder_prereq_unmet", message: "#{e.reason}: #{e.message}", status: :unprocessable_entity)
      rescue ActiveRecord::RecordNotUnique
        render_error(code: "wonder_already_active", message: "wonder already in progress", status: :unprocessable_entity)
      rescue ::Stockpile::Apply::InsufficientResources => e
        render_error(code: "insufficient_resources", message: e.message, status: :unprocessable_entity)
      end

      def destroy
        kingdom = load_owned_kingdom
        wonder = load_wonder(kingdom)
        raise ActiveRecord::RecordNotFound, "no wonder" if wonder.nil? || !wonder.live?

        ::Wonders::Cancel.call(wonder: wonder)
        render json: self.class.serialize(wonder.reload)
      end

      def repair
        kingdom = load_owned_kingdom
        wonder = load_wonder(kingdom)
        raise ActiveRecord::RecordNotFound, "no wonder" if wonder.nil?

        hp = params.require(:hp).to_i
        ::Wonders::Repair.call(wonder: wonder, hp: hp)
        render json: self.class.serialize(wonder.reload)
      rescue ::Wonders::Repair::NotRepairable => e
        render_error(code: "wonder_not_repairable", message: e.message, status: :unprocessable_entity)
      rescue ::Wonders::Repair::InvalidAmount => e
        render_error(code: "invalid_amount", message: e.message, status: :unprocessable_entity)
      rescue ::Wonders::Repair::CapReached => e
        render_error(code: "repair_cap_reached", message: e.message, status: :unprocessable_entity)
      rescue ::Stockpile::Apply::InsufficientResources => e
        render_error(code: "insufficient_resources", message: e.message, status: :unprocessable_entity)
      end

      def milestone
        kingdom = load_owned_kingdom
        wonder = load_wonder(kingdom)
        raise ActiveRecord::RecordNotFound, "no wonder" if wonder.nil?

        percent = params.require(:percent).to_i
        ::Wonders::PayMilestone.call(wonder: wonder, percent: percent)
        render json: self.class.serialize(wonder.reload)
      rescue ::Wonders::PayMilestone::NoMilestonePending => e
        render_error(code: "no_milestone_pending", message: e.message, status: :unprocessable_entity)
      rescue ::Wonders::PayMilestone::WrongPercent => e
        render_error(code: "wrong_milestone_percent", message: e.message, status: :unprocessable_entity)
      rescue ::Wonders::PayMilestone::AlreadyPaid => e
        render_error(code: "milestone_already_paid", message: e.message, status: :unprocessable_entity)
      rescue ::Stockpile::Apply::InsufficientResources => e
        render_error(code: "insufficient_resources", message: e.message, status: :unprocessable_entity)
      end

      def self.serialize(wonder)
        pending_cost = wonder.pending_milestone_percent ? ::Wonders::Catalog.milestone_cost : nil
        {
          id: wonder.id,
          kingdom_id: wonder.kingdom_id,
          world_id: wonder.kingdom.world_id,
          name: wonder.name,
          status: wonder.status,
          hp: wonder.hp,
          target_hp: wonder.target_hp,
          milestones_paid: wonder.milestones_paid,
          pending_milestone_percent: wonder.pending_milestone_percent,
          pending_milestone_cost: pending_cost,
          repaired_hp_by_phase: wonder.repaired_hp_by_phase,
          paused_until: wonder.paused_until&.iso8601,
          started_at: wonder.started_at&.iso8601,
          construction_started_at: wonder.construction_started_at&.iso8601,
          consecration_at: wonder.consecration_at&.iso8601,
          completed_at: wonder.completed_at&.iso8601,
          destroyed_at: wonder.destroyed_at&.iso8601
        }
      end

      private

      def load_owned_kingdom
        kingdom = ::Kingdom.find(params[:kingdom_id])
        profile = ::PlayerProfile.find_by(server_id: kingdom.world.server_id, player_id: Current.player.id)
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if profile.nil?
        raise ActiveRecord::RecordNotFound, "kingdom not visible" if kingdom.player_profile_id != profile.id

        kingdom
      end

      def load_wonder(kingdom)
        ::Wonder.where(kingdom_id: kingdom.id).order(created_at: :desc).first
      end
    end
  end
end
