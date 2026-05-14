class CreateBuildOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :build_orders, id: :string do |t|
      t.references :kingdom, null: false, foreign_key: true, type: :string
      t.references :building, null: false, foreign_key: true, type: :string
      t.integer :target_level, null: false
      t.datetime :started_at, null: false
      t.datetime :completes_at, null: false
      t.datetime :cancelled_at
      t.datetime :completed_at
      t.timestamps

      t.index :completes_at
      t.index :kingdom_id,
        name: "index_build_orders_on_kingdom_id_unresolved",
        where: "completed_at IS NULL AND cancelled_at IS NULL"
    end
  end
end
