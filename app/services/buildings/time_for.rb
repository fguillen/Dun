module Buildings
  class TimeFor
    def self.call(kind:, level:, kingdom: nil)
      new(kind: kind, level: level, kingdom: kingdom).call
    end

    def initialize(kind:, level:, kingdom:)
      @kind = kind.to_s
      @level = level.to_i
      @kingdom = kingdom
    end

    def call
      raise ArgumentError, "unknown building kind #{@kind}" unless Catalog.kind?(@kind)
      raise ArgumentError, "level must be >= 1" if @level < 1

      base = Catalog::BASE_TIMES.fetch(@kind)
      raw = base * (Catalog::TIME_GROWTH**(@level - 1))
      capped = [ raw, Catalog::TIME_CAP.to_i ].min
      discounted = capped * (1 - stone_mason_discount)
      discounted.round.seconds
    end

    private

    def stone_mason_discount
      return 0.0 if @kingdom.nil?

      level = @kingdom.buildings.where(kind: "stone_mason").pick(:level).to_i
      [ Catalog::STONE_MASON_DISCOUNT_PER_LEVEL * level, Catalog::STONE_MASON_DISCOUNT_MAX ].min
    end
  end
end
