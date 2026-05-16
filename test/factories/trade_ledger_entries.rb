FactoryBot.define do
  factory :trade_ledger_entry do
    association :caravan
    world { caravan.world }
    sender_handle_at_send   { "Sender" }
    receiver_handle_at_send { "Receiver" }
    resource     { "gold" }
    amount       { 100 }
    status       { "in_transit" }
    recorded_at  { Time.current }
  end
end
