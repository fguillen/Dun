require "test_helper"

module TradeLedger
  class RecordTest < ActiveSupport::TestCase
    def setup
      @server = create(:server)
      @world  = create(:world, :active, server: @server)

      @sender_profile   = create(:player_profile, server: @server, handle: "Alice")
      @receiver_profile = create(:player_profile, server: @server, handle: "Bob")
      @sender   = create(:kingdom, world: @world, player_profile: @sender_profile)
      @receiver = create(:kingdom, world: @world, player_profile: @receiver_profile)

      @caravan = create(:caravan,
        world: @world,
        sender_kingdom: @sender,
        receiver_kingdom: @receiver,
        payload: { "gold" => 100, "wood" => 0, "stone" => 50, "iron" => 0 })
    end

    test "creates one entry per non-zero resource on first call" do
      TradeLedger::Record.call(caravan: @caravan, status: "in_transit")

      entries = @caravan.ledger_entries.order(:resource)
      assert_equal 2, entries.size
      assert_equal %w[gold stone], entries.map(&:resource)
      assert_equal [ 100, 50 ], entries.map(&:amount)
      assert entries.all? { |e| e.status == "in_transit" }
      assert entries.all? { |e| e.sender_handle_at_send == "Alice" }
      assert entries.all? { |e| e.receiver_handle_at_send == "Bob" }
      assert entries.all? { |e| e.attacker_handle.nil? }
    end

    test "second call updates existing entries in place (no duplicates)" do
      TradeLedger::Record.call(caravan: @caravan, status: "in_transit")
      assert_equal 2, @caravan.ledger_entries.count

      TradeLedger::Record.call(caravan: @caravan, status: "delivered")
      assert_equal 2, @caravan.ledger_entries.count
      assert @caravan.ledger_entries.all? { |e| e.status == "delivered" }
    end

    test "intercept sets attacker_handle on existing entries" do
      TradeLedger::Record.call(caravan: @caravan, status: "in_transit")
      TradeLedger::Record.call(caravan: @caravan, status: "intercepted", attacker_handle: "Eve")

      assert @caravan.ledger_entries.all? { |e| e.status == "intercepted" }
      assert @caravan.ledger_entries.all? { |e| e.attacker_handle == "Eve" }
    end

    test "snapshots handles even if profile handle changes later" do
      TradeLedger::Record.call(caravan: @caravan, status: "in_transit")
      @sender_profile.update!(handle: "Renamed")

      assert @caravan.ledger_entries.all? { |e| e.sender_handle_at_send == "Alice" }
    end

    test "falls back to [unknown] when sender has no handle" do
      @sender_profile.update!(handle: nil)
      TradeLedger::Record.call(caravan: @caravan, status: "in_transit")

      assert @caravan.ledger_entries.all? { |e| e.sender_handle_at_send == "[unknown]" }
    end
  end
end
