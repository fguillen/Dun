class CreateTradeLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :trade_ledger_entries, id: :string do |t|
      t.references :world, null: false, foreign_key: true, type: :string
      t.references :caravan, null: false, foreign_key: true, type: :string
      t.string :sender_handle_at_send, null: false
      t.string :receiver_handle_at_send, null: false
      t.string :attacker_handle
      t.string :resource, null: false
      t.bigint :amount, null: false
      t.string :status, null: false
      t.datetime :recorded_at, null: false
      t.timestamps

      t.index [ :world_id, :recorded_at ]
      t.index [ :world_id, :sender_handle_at_send ]
      t.index [ :world_id, :receiver_handle_at_send ]
      t.index [ :world_id, :attacker_handle ]
      t.index [ :caravan_id, :resource ], unique: true
    end
  end
end
