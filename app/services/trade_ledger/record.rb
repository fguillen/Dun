module TradeLedger
  # Writes / updates the per-resource ledger entries for a caravan.
  #
  # Called three times per caravan:
  #   - on Dispatch: status: "in_transit"  — creates one row per non-zero resource
  #   - on Deliver:  status: "delivered"   — updates existing rows in place
  #   - on Intercept: status: "intercepted", attacker_handle: "..."
  class Record
    def self.call(caravan:, status:, attacker_handle: nil)
      new(caravan: caravan, status: status, attacker_handle: attacker_handle).call
    end

    def initialize(caravan:, status:, attacker_handle:)
      @caravan = caravan
      @status = status.to_s
      @attacker_handle = attacker_handle
    end

    def call
      ActiveRecord::Base.transaction do
        existing = @caravan.ledger_entries.lock.to_a
        if existing.empty?
          create_entries
        else
          update_entries(existing)
        end
      end
    end

    private

    def create_entries
      sender_handle   = @caravan.sender_kingdom.handle
      receiver_handle = @caravan.receiver_kingdom.handle
      now = Time.current

      Kingdom::RESOURCES.each_with_object([]) do |resource, rows|
        amount = @caravan.payload[resource].to_i
        next if amount.zero?

        rows << @caravan.ledger_entries.create!(
          world_id: @caravan.world_id,
          sender_handle_at_send: sender_handle,
          receiver_handle_at_send: receiver_handle,
          attacker_handle: @attacker_handle,
          resource: resource,
          amount: amount,
          status: @status,
          recorded_at: now
        )
      end
    end

    def update_entries(entries)
      now = Time.current
      entries.each do |entry|
        entry.update!(
          status: @status,
          attacker_handle: @attacker_handle || entry.attacker_handle,
          recorded_at: now
        )
      end
      entries
    end
  end
end
