module Api
  class ArmiesController < Api::BaseController
    def show
      army = load_owned_army
      render json: self.class.serialize(army)
    end

    def split
      army = load_owned_army
      units = (params[:units] || {}).to_unsafe_h.transform_values(&:to_i)
      name = params.require(:name).to_s

      result = ::Armies::Split.call(army: army, units: units, name: name)
      render json: {
        source: result[:source] && self.class.serialize(result[:source].reload),
        new: self.class.serialize(result[:new])
      }, status: :created
    rescue ::Armies::Split::NotHome => e
      render_error(code: "army_not_home", message: e.message, status: :unprocessable_entity)
    rescue ::Armies::Split::InsufficientUnits => e
      render_error(code: "insufficient_units", message: e.message, status: :unprocessable_entity)
    rescue ::Armies::Split::EmptySplit => e
      render_error(code: "empty_split", message: e.message, status: :unprocessable_entity)
    rescue ActiveRecord::RecordInvalid => e
      render_error(code: "invalid_army", message: e.message, status: :unprocessable_entity)
    end

    def rename
      army = load_owned_army
      name = params.require(:name).to_s

      ::Armies::Rename.call(army: army, name: name)
      render json: self.class.serialize(army.reload)
    rescue ::Armies::Rename::NameTaken => e
      render_error(code: "name_taken", message: e.message, status: :unprocessable_entity)
    end

    def merge
      into = load_owned_army
      from = into.kingdom.armies.find(params.require(:from_id))

      ::Armies::Merge.call(into: into, from: from)
      render json: self.class.serialize(into.reload)
    rescue ::Armies::Merge::IncompatibleKingdom,
           ::Armies::Merge::IncompatibleLocation,
           ::Armies::Merge::IncompatibleStatus => e
      render_error(code: "incompatible_armies", message: e.message, status: :unprocessable_entity)
    end

    def self.serialize(army)
      {
        id: army.id,
        kingdom_id: army.kingdom_id,
        name: army.name,
        status: army.status,
        location_region_id: army.location_region_id,
        composition: army.composition,
        total_capacity: army.total_capacity
      }
    end

    private

    def load_owned_army
      army = Army.find(params[:id])
      profile = PlayerProfile.find_by(server_id: army.kingdom.world.server_id, player_id: Current.player.id)
      raise ActiveRecord::RecordNotFound, "army not visible" if profile.nil?
      raise ActiveRecord::RecordNotFound, "army not visible" if army.kingdom.player_profile_id != profile.id

      army
    end
  end
end
