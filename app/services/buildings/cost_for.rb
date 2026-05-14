module Buildings
  class CostFor
    def self.call(kind:, level:)
      new(kind: kind, level: level).call
    end

    def initialize(kind:, level:)
      @kind = kind.to_s
      @level = level.to_i
    end

    def call
      raise ArgumentError, "unknown building kind #{@kind}" unless Catalog.kind?(@kind)
      raise ArgumentError, "level must be >= 1" if @level < 1

      base = Catalog::BASE_COSTS.fetch(@kind)
      multiplier = Catalog::COST_GROWTH**(@level - 1)
      base.each_with_object({}) do |(resource, value), out|
        out[resource] = (value * multiplier).round
      end
    end
  end
end
