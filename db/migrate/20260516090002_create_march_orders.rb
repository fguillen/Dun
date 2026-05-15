class CreateMarchOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :march_orders, id: :string do |t|
      t.references :army, null: false, foreign_key: true, type: :string
      t.references :origin_region, null: false, foreign_key: { to_table: :regions }, type: :string
      t.references :target_region, null: false, foreign_key: { to_table: :regions }, type: :string
      t.string :intent, null: false
      t.jsonb :path, null: false, default: []
      t.jsonb :escort_units
      t.jsonb :cargo
      t.datetime :dispatched_at, null: false
      t.datetime :arrives_at, null: false
      t.datetime :recalled_at
      t.datetime :arrived_at
      t.timestamps

      t.index :arrives_at
      t.index :army_id,
        name: "index_march_orders_on_army_id_active",
        where: "arrived_at IS NULL AND recalled_at IS NULL"
      t.index [ :target_region_id, :arrives_at ],
        name: "index_march_orders_by_target_arrival"
    end
  end
end
