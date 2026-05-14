module Stockpile
  class Apply
    class InsufficientResources < StandardError
      attr_reader :resource, :short_by

      def initialize(resource, short_by)
        @resource = resource
        @short_by = short_by
        super("insufficient #{resource} (short by #{short_by})")
      end
    end

    def self.call(kingdom:, deltas:)
      new(kingdom: kingdom, deltas: deltas).call
    end

    def initialize(kingdom:, deltas:)
      @kingdom = kingdom
      @deltas = deltas
    end

    def call
      ActiveRecord::Base.transaction do
        kingdom = Kingdom.lock.find(@kingdom.id)
        materialized = Stockpile::Read.call(kingdom)

        warehouse_level = kingdom.buildings.where(kind: "warehouse").pick(:level).to_i
        cap = Buildings::Catalog.warehouse_cap(warehouse_level)

        new_stockpiles = {}
        Kingdom::RESOURCES.each do |resource|
          delta = (@deltas[resource] || @deltas[resource.to_sym] || 0).to_i
          raw = materialized[resource] + delta
          if raw < 0
            raise InsufficientResources.new(resource, -raw)
          end
          new_stockpiles[resource] = [ raw, cap ].min
        end
        new_stockpiles["checkpoint_at"] = Time.current.iso8601

        kingdom.update!(stockpiles: new_stockpiles)
        @kingdom.reload
        @kingdom
      end
    end
  end
end
