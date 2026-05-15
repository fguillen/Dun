module Training
  class ResolveCompletions
    def self.call(kingdom)
      new(kingdom).call
    end

    def initialize(kingdom)
      @kingdom = kingdom
    end

    def call
      loop do
        ripe = @kingdom.training_orders.ripe.order(:completes_at).first
        break if ripe.nil?

        Training::Complete.call(training_order: ripe)
      end
      @kingdom
    end
  end
end
