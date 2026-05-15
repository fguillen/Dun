module Marches
  class Dispatch
    class NotHome < StandardError; end
    class WorldNotActive < StandardError; end
    class InvalidIntent < StandardError; end

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
  end
end
