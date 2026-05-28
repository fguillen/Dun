module Events
  # Aggregates the events a player can see for one of their kingdoms into a
  # single chronological feed. Reads existing durable records (no event table):
  # the kingdom's own builds/trainings/marches/battles/captures plus the
  # world-public trade ledger and every wonder's phase changes.
  #
  # Returns the most-recent `limit` events ordered oldest-first.
  class Feed
    Event = Data.define(:occurred_at, :type, :description)

    def self.call(kingdom:, limit: 10)
      new(kingdom: kingdom, limit: limit).call
    end

    def initialize(kingdom:, limit:)
      @kingdom = kingdom
      @world   = kingdom.world
      @limit   = limit
    end

    def call
      [ builds, trainings, marches, battles, captures, wonders, trades ]
        .flatten
        .sort_by { |e| [ e.occurred_at, e.type ] }
        .last(@limit)
    end

    private

    def builds
      @kingdom.build_orders
              .where.not(completed_at: nil)
              .order(completed_at: :desc)
              .limit(@limit)
              .includes(:building)
              .map do |order|
        Event.new(
          occurred_at: order.completed_at,
          type: "build",
          description: %(Building "#{order.building.kind}" finished upgrading to L#{order.target_level}.)
        )
      end
    end

    def trainings
      @kingdom.training_orders
              .where.not(completed_at: nil)
              .order(completed_at: :desc)
              .limit(@limit)
              .map do |order|
        Event.new(
          occurred_at: order.completed_at,
          type: "training",
          description: "Trained #{order.count} #{order.unit} at the #{order.building_kind}."
        )
      end
    end

    def marches
      kingdom_marches
        .order(dispatched_at: :desc)
        .limit(@limit)
        .includes(:army, :target_region)
        .map do |march|
        Event.new(
          occurred_at: march.dispatched_at,
          type: "march",
          description: %(Army "#{march.army.name}" marched to #{march.target_region.name} (#{march.intent}).)
        )
      end
    end

    def battles
      Battle.involving(@kingdom.id)
            .order(ended_at: :desc)
            .limit(@limit)
            .includes(:region)
            .map do |battle|
        role = battle.attacker_kingdom_id == @kingdom.id ? "Attacked" : "Defended"
        Event.new(
          occurred_at: battle.ended_at,
          type: "battle",
          description: "#{role} at #{battle.region.name} — #{battle.outcome.tr('_', ' ')}."
        )
      end
    end

    # No dedicated captured_at exists. Approximate: a capture-march that arrived
    # and left this kingdom owning a node in the target region.
    def captures
      kingdom_marches
        .where(intent: "capture")
        .where.not(arrived_at: nil)
        .order(arrived_at: :desc)
        .limit(@limit)
        .includes(:target_region)
        .select { |march| owns_node_in?(march.target_region_id) }
        .map do |march|
        Event.new(
          occurred_at: march.arrived_at,
          type: "capture",
          description: "Captured a node in #{march.target_region.name}."
        )
      end
    end

    def wonders
      wonder_phase_events + wonder_damage_events
    end

    # World-public: every wonder's phase transitions.
    def wonder_phase_events
      world_wonders.flat_map do |wonder|
        [
          phase_event(wonder, wonder.construction_started_at, "began construction"),
          phase_event(wonder, wonder.consecration_at, "entered consecration"),
          phase_event(wonder, wonder.completed_at, "was completed"),
          phase_event(wonder, wonder.destroyed_at, "was destroyed")
        ].compact
      end
    end

    # Own involvement only: damage this kingdom dealt or took on its own Wonder.
    def wonder_damage_events
      own_wonder_ids = world_wonders.select { |w| w.kingdom_id == @kingdom.id }.map(&:id)

      scope = WonderDamageEvent.where(attacker_kingdom_id: @kingdom.id)
      scope = scope.or(WonderDamageEvent.where(wonder_id: own_wonder_ids)) if own_wonder_ids.any?

      scope.order(occurred_at: :desc)
           .limit(@limit)
           .includes(:wonder)
           .map do |damage|
        Event.new(
          occurred_at: damage.occurred_at,
          type: "wonder",
          description: %(Wonder "#{damage.wonder.name}" took damage (#{damage.hp_before} -> #{damage.hp_after} HP).)
        )
      end
    end

    # World-public trade ledger: dispatch plus terminal status per caravan.
    def trades
      Caravan.where(world_id: @world.id)
             .order(dispatched_at: :desc)
             .limit(@limit)
             .includes(sender_kingdom: :player_profile, receiver_kingdom: :player_profile)
             .flat_map { |caravan| caravan_events(caravan) }
    end

    def caravan_events(caravan)
      summary = payload_summary(caravan)
      sender = caravan.sender_kingdom.handle
      receiver = caravan.receiver_kingdom.handle

      events = [
        Event.new(
          occurred_at: caravan.dispatched_at,
          type: "trade",
          description: "Caravan dispatched: #{summary} from #{sender} to #{receiver}."
        )
      ]

      if caravan.delivered_at
        events << Event.new(
          occurred_at: caravan.delivered_at,
          type: "trade",
          description: "Caravan delivered #{summary} to #{receiver}."
        )
      elsif caravan.intercepted_at
        events << Event.new(
          occurred_at: caravan.intercepted_at,
          type: "trade",
          description: "Caravan from #{sender} to #{receiver} was intercepted (#{summary} lost)."
        )
      end

      events
    end

    def phase_event(wonder, occurred_at, verb)
      return nil if occurred_at.nil?

      Event.new(
        occurred_at: occurred_at,
        type: "wonder",
        description: %(Wonder "#{wonder.name}" #{verb}.)
      )
    end

    def kingdom_marches
      MarchOrder.joins(:army).where(armies: { kingdom_id: @kingdom.id })
    end

    def owns_node_in?(region_id)
      Node.where(region_id: region_id, owner_kingdom_id: @kingdom.id).exists?
    end

    def world_wonders
      @world_wonders ||= Wonder.joins(:kingdom).where(kingdoms: { world_id: @world.id }).to_a
    end

    def payload_summary(caravan)
      caravan.payload
             .select { |_, amount| amount.to_i.positive? }
             .map { |resource, amount| "#{amount} #{resource}" }
             .join(", ")
    end
  end
end
