module Buildings
  class ResolveCompletions
    def self.call(kingdom)
      new(kingdom).call
    end

    def initialize(kingdom)
      @kingdom = kingdom
    end

    def call
      loop do
        ripe = @kingdom.build_orders.ripe.order(:completes_at).first
        break if ripe.nil?

        Buildings::Complete.call(build_order: ripe)
      end
      @kingdom
    end
  end
end
