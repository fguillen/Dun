module Marches
  class Dispatch
    class NotHome < StandardError; end
    class WorldNotActive < StandardError; end
    class InvalidIntent < StandardError; end
    class CatapultRequired < StandardError; end
    class NoCapturableNode < StandardError; end
    class SelfCapture < StandardError; end
    class HomeHoardProtected < StandardError; end
    class SelfAttack < StandardError; end

    DISPATCHABLE_WORLD_STATUSES = %w[grace active].freeze

    def self.call(army:, target_region:, intent:)
      new(army: army, target_region: target_region, intent: intent).call
    end

    def initialize(army:, target_region:, intent:)
      @army = army
      @target_region = target_region
      @intent = intent.to_s
    end

    def call
      ActiveRecord::Base.transaction do
        army = Army.lock.find(@army.id)
        raise NotHome, "army must be home to dispatch" unless army.status == "home"
        raise InvalidIntent, "unknown intent #{@intent}" unless MarchOrder::INTENTS.include?(@intent)

        kingdom = army.kingdom
        raise WorldNotActive, "world status #{kingdom.world.status} not dispatchable" unless DISPATCHABLE_WORLD_STATUSES.include?(kingdom.world.status)

        validate_feasibility!(army, kingdom)

        plan = Marches::Plan.call(origin: army.location_region, destination: @target_region, army: army)

        now = Time.current
        order = MarchOrder.create!(
          army: army,
          origin_region_id: army.location_region_id,
          target_region_id: @target_region.id,
          intent: @intent,
          path: plan.path,
          dispatched_at: now,
          arrives_at: now + plan.total_seconds
        )

        army.update!(status: "marching")

        ScheduledEvents::Schedule.call(
          world: kingdom.world,
          kind: "march_arrival",
          fire_at: order.arrives_at,
          payload: { "march_order_id" => order.id }
        )

        ActiveSupport::Notifications.instrument(
          "dun.march_order.dispatched",
          world_id: kingdom.world_id,
          kingdom_id: kingdom.id,
          army_id: army.id,
          march_order_id: order.id,
          intent: @intent,
          target_region_id: @target_region.id,
          arrives_at: order.arrives_at
        )

        order
      end
    end

    private

    # Reject marches that can never succeed, up front, so the caller gets a
    # synchronous error code instead of discovering it on arrival. `capture`
    # preconditions are deterministic at dispatch; the service re-checks them on
    # arrival as a backstop for state that changes in transit.
    def validate_feasibility!(army, kingdom)
      case @intent
      when "capture"
        node = Node.where(region_id: @target_region.id).first
        raise NoCapturableNode, "region #{@target_region.id} has no node to capture" if node.nil?
        raise SelfCapture, "kingdom #{army.kingdom_id} already owns node #{node.id}" if node.owner_kingdom_id == army.kingdom_id
        raise HomeHoardProtected, "node #{node.id} is a home-hoard reserved for its home kingdom" if foreign_home_hoard?(node, army.kingdom_id)
        raise CatapultRequired, "capture requires a catapult (§9)" if army.composition["catapult"].to_i < 1
      when "attack"
        raise SelfAttack, "cannot raid your own home region" if @target_region.id == kingdom.home_region_id
      end
    end

    def foreign_home_hoard?(node, kingdom_id)
      return false unless node.is_home_hoard?
      rightful = Kingdom.find_by(world_id: @target_region.world_id, home_region_id: @target_region.id)
      rightful.nil? || rightful.id != kingdom_id
    end
  end
end
