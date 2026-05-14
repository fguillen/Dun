module Stockpile
  class Read
    def self.call(kingdom)
      new(kingdom).call
    end

    def initialize(kingdom)
      @kingdom = kingdom
    end

    def call
      stored = @kingdom.stockpiles || {}
      checkpoint_at = parse_checkpoint(stored["checkpoint_at"])
      elapsed_seconds = [ Time.current - checkpoint_at, 0 ].max
      elapsed_hours = elapsed_seconds / 3600.0

      warehouse_level = @kingdom.buildings.where(kind: "warehouse").pick(:level).to_i
      cap = Buildings::Catalog.warehouse_cap(warehouse_level)

      Kingdom::RESOURCES.each_with_object({}) do |resource, out|
        rate = Production::RateFor.call(kingdom: @kingdom, resource: resource)
        raw = stored[resource].to_i + (rate * elapsed_hours)
        out[resource] = [ raw.floor, cap ].min
      end
    end

    private

    def parse_checkpoint(value)
      return Time.current if value.blank?
      Time.iso8601(value.to_s)
    rescue ArgumentError
      Time.current
    end
  end
end
