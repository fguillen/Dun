module Wonders
  # Validates a kingdom can start a Wonder. Raises NotMet with a reason code
  # on the first failed check.
  class Prerequisites
    class NotMet < StandardError
      attr_reader :reason

      def initialize(reason, message = nil)
        @reason = reason
        super(message || reason)
      end
    end

    def self.call(kingdom:)
      new(kingdom).call
    end

    def initialize(kingdom)
      @kingdom = kingdom
    end

    def call
      raise NotMet.new("world_not_active", "world status is #{@kingdom.world.status}, must be active") unless @kingdom.world.active?
      raise NotMet.new("kingdom_eliminated", "kingdom is eliminated") if @kingdom.eliminated?

      Catalog::PREREQUISITES.each do |kind, required|
        level = @kingdom.buildings.where(kind: kind).pick(:level).to_i
        if level < required
          raise NotMet.new("need_#{kind}_level_#{required}", "#{kind} level #{required} required (have #{level})")
        end
      end

      owned_nodes = Node.where(owner_kingdom_id: @kingdom.id).count
      if owned_nodes < Catalog::NODES_REQUIRED
        raise NotMet.new("need_#{Catalog::NODES_REQUIRED}_nodes", "control #{Catalog::NODES_REQUIRED} nodes (have #{owned_nodes})")
      end

      if Wonders::LiveFor.call(@kingdom).present?
        raise NotMet.new("wonder_already_active", "an existing Wonder is in progress")
      end

      stockpile = Stockpile::Read.call(@kingdom)
      Catalog.foundation_cost.each do |resource, cost|
        if stockpile[resource].to_i < cost
          raise NotMet.new("insufficient_resources", "need #{cost} #{resource} for foundation (have #{stockpile[resource].to_i})")
        end
      end

      true
    end
  end
end
