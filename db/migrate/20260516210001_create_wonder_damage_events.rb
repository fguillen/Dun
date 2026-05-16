class CreateWonderDamageEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :wonder_damage_events, id: :string do |t|
      t.references :wonder, null: false, foreign_key: true, type: :string
      t.references :attacker_kingdom, null: false, foreign_key: { to_table: :kingdoms }, type: :string
      t.references :battle, null: true, foreign_key: { on_delete: :nullify }, type: :string
      t.integer :trebuchets_surviving, null: false
      t.integer :hp_before, null: false
      t.integer :hp_after, null: false
      t.datetime :occurred_at, null: false
      t.timestamps

      t.index [ :wonder_id, :occurred_at ]
    end
  end
end
