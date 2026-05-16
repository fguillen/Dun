class CreateCaravans < ActiveRecord::Migration[8.1]
  def change
    create_table :caravans, id: :string do |t|
      t.references :world, null: false, foreign_key: true, type: :string
      t.references :sender_kingdom, null: false, foreign_key: { to_table: :kingdoms }, type: :string
      t.references :receiver_kingdom, null: false, foreign_key: { to_table: :kingdoms }, type: :string
      t.references :origin_region, null: false, foreign_key: { to_table: :regions }, type: :string
      t.references :destination_region, null: false, foreign_key: { to_table: :regions }, type: :string
      # The escort army and its march orders can be destroyed by combat or by
      # the Army -> MarchOrder dependent: :destroy cascade. The Caravan record
      # is the historical anchor and outlives those operational rows, so the
      # FKs nullify rather than cascade-delete the caravan.
      t.references :escort_army, null: true, foreign_key: { to_table: :armies, on_delete: :nullify }, type: :string
      t.references :outbound_march_order, null: true, foreign_key: { to_table: :march_orders, on_delete: :nullify }, type: :string, index: { unique: true }
      t.references :return_march_order, null: true, foreign_key: { to_table: :march_orders, on_delete: :nullify }, type: :string, index: { unique: true }
      t.jsonb :payload, null: false, default: {}
      t.jsonb :escort_units, null: false, default: {}
      t.string :status, null: false, default: "in_transit"
      t.datetime :dispatched_at, null: false
      t.datetime :arrives_at, null: false
      t.datetime :delivered_at
      t.datetime :intercepted_at
      t.timestamps

      t.index [ :world_id, :status ]
    end
  end
end
