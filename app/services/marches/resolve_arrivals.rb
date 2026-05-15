module Marches
  class ResolveArrivals
    def self.call(kingdom)
      new(kingdom).call
    end

    def initialize(kingdom)
      @kingdom = kingdom
    end

    def call
      loop do
        ripe = MarchOrder.ripe
          .where(army_id: @kingdom.armies.select(:id))
          .order(:arrives_at)
          .first
        break if ripe.nil?

        Marches::Arrive.call(march_order: ripe)
      end
      @kingdom
    end
  end
end
