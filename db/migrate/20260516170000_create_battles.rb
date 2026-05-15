class CreateBattles < ActiveRecord::Migration[8.1]
  def change
    create_table :battles, id: :string do |t|
      t.references :world, null: false, foreign_key: true, type: :string
      t.references :region, null: false, foreign_key: true, type: :string
      t.references :attacker_kingdom, null: false, foreign_key: { to_table: :kingdoms }, type: :string
      t.references :defender_kingdom, null: false, foreign_key: { to_table: :kingdoms }, type: :string
      t.references :march_order, foreign_key: true, type: :string
      t.string :outcome, null: false
      t.jsonb :loot, null: false, default: {}
      t.jsonb :log, null: false, default: []
      t.string :variance_seed
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.timestamps

      t.index [ :world_id, :ended_at ]
      t.index [ :attacker_kingdom_id, :ended_at ]
      t.index [ :defender_kingdom_id, :ended_at ]
    end
  end
end
