module Api
  module Admin
    module Worlds
      class BattlesController < Api::Admin::BaseController
        DEFAULT_LIMIT = 25
        MAX_LIMIT = 100

        def index
          limit = clamp_limit(params[:limit])
          offset = params[:offset].to_i.clamp(0, 1_000_000)

          scope = Battle.where(world_id: world.id).order(ended_at: :desc, id: :desc)
          total = scope.count
          battles = scope.limit(limit).offset(offset)

          render json: {
            battles: battles.map { |b| Api::BattlesController.serialize(b) },
            total_count: total
          }
        end

        private

        def clamp_limit(raw)
          return DEFAULT_LIMIT if raw.blank?
          raw.to_i.clamp(1, MAX_LIMIT)
        end

        def world
          @world ||= World
            .joins(server: :server_adminships)
            .where(server_adminships: { admin_id: Current.admin.id })
            .find(params[:world_id])
        end
      end
    end
  end
end
