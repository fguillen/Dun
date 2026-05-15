class CreateArmies < ActiveRecord::Migration[8.1]
  def change
    create_table :armies, id: :string do |t|
      t.references :kingdom, null: false, foreign_key: true, type: :string
      t.references :location_region, null: false, foreign_key: { to_table: :regions }, type: :string
      t.string :name, null: false
      t.string :status, null: false, default: "home"
      t.jsonb :composition, null: false, default: {}
      t.timestamps

      t.index [ :kingdom_id, :status ]
      t.index [ :kingdom_id, :name ], unique: true
    end
  end
end
