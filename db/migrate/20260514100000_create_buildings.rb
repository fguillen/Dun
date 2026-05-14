class CreateBuildings < ActiveRecord::Migration[8.1]
  def change
    create_table :buildings, id: :string do |t|
      t.references :kingdom, null: false, foreign_key: true, type: :string
      t.string :kind, null: false
      t.integer :level, null: false, default: 0
      t.jsonb :position
      t.timestamps

      t.index [ :kingdom_id, :kind ], unique: true
    end
  end
end
