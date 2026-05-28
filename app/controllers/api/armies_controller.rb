module Api
  class ArmiesController < Api::BaseController
    def show
      army = load_owned_army
      ::Marches::ResolveArrivals.call(army.kingdom)
      army.reload
      render json: self.class.serialize(army)
    end

    def march
      army = load_owned_army
      target = army.kingdom.world.regions.find(params.require(:target_region_id))
      intent = params.require(:intent).to_s

      order = ::Marches::Dispatch.call(army: army, target_region: target, intent: intent)
      render json: serialize_march(order), status: :created
    rescue ::Marches::Dispatch::NotHome => e
      render_error(code: "army_not_home", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Dispatch::WorldNotActive => e
      render_error(code: "world_not_active", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Dispatch::InvalidIntent => e
      render_error(code: "invalid_intent", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Dispatch::CatapultRequired => e
      render_error(code: "catapult_required", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Dispatch::NoCapturableNode => e
      render_error(code: "no_capturable_node", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Dispatch::SelfCapture => e
      render_error(code: "self_capture", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Dispatch::HomeHoardProtected => e
      render_error(code: "home_hoard_protected", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Dispatch::SelfAttack => e
      render_error(code: "self_attack", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Plan::EmptyArmy => e
      render_error(code: "army_empty", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Plan::CrossWorld => e
      render_error(code: "cross_world", message: e.message, status: :unprocessable_entity)
    rescue ::Marches::Plan::Unreachable => e
      render_error(code: "unreachable", message: e.message, status: :unprocessable_entity)
    end

    def recall
      army = load_owned_army
      active = army.march_orders.active.order(:arrives_at).first
      raise ActiveRecord::RecordNotFound, "no active march order" if active.nil?

      return_order = ::Marches::Recall.call(march_order: active)
      render json: serialize_march(return_order)
    rescue ::Marches::Recall::AlreadyResolved => e
      render_error(code: "march_already_resolved", message: e.message, status: :unprocessable_entity)
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
        total_capacity: army.total_capacity,
        active_march: serialize_active_march(army)
      }
    end

    # Embedded so clients can render a march ETA; there is no GET endpoint for marches. Null unless the army is in flight.
    def self.serialize_active_march(army)
      return nil unless army.status.in?(%w[marching returning])

      order = army.march_orders.detect(&:active?)
      return nil if order.nil?

      {
        march_order_id: order.id,
        intent: order.intent,
        target_region_id: order.target_region_id,
        arrives_at: order.arrives_at&.iso8601,
        dispatched_at: order.dispatched_at&.iso8601
      }
    end

    def self.serialize_march(order)
      {
        id: order.id,
        army_id: order.army_id,
        intent: order.intent,
        origin_region_id: order.origin_region_id,
        target_region_id: order.target_region_id,
        path: order.path,
        dispatched_at: order.dispatched_at&.iso8601,
        arrives_at: order.arrives_at&.iso8601,
        arrived_at: order.arrived_at&.iso8601,
        recalled_at: order.recalled_at&.iso8601
      }
    end

    private

    def serialize_march(order)
      self.class.serialize_march(order)
    end


    def load_owned_army
      army = Army.find(params[:id])
      profile = PlayerProfile.find_by(server_id: army.kingdom.world.server_id, player_id: Current.player.id)
      raise ActiveRecord::RecordNotFound, "army not visible" if profile.nil?
      raise ActiveRecord::RecordNotFound, "army not visible" if army.kingdom.player_profile_id != profile.id

      army
    end
  end
end
