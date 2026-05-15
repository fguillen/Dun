class CreateTrainingOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :training_orders, id: :string do |t|
      t.references :kingdom, null: false, foreign_key: true, type: :string
      t.references :building, null: false, foreign_key: true, type: :string
      t.string :building_kind, null: false
      t.string :unit, null: false
      t.integer :count, null: false
      t.datetime :started_at, null: false
      t.datetime :completes_at, null: false
      t.datetime :cancelled_at
      t.datetime :completed_at
      t.timestamps

      t.index :completes_at
      t.index :kingdom_id,
        name: "index_training_orders_on_kingdom_id_unresolved",
        where: "completed_at IS NULL AND cancelled_at IS NULL"
      t.index :building_id,
        name: "index_training_orders_on_building_id_unresolved",
        where: "completed_at IS NULL AND cancelled_at IS NULL"
    end
  end
end
