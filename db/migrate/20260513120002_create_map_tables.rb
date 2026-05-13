class CreateMapTables < ActiveRecord::Migration[8.1]
  def change
    create_table :regions do |t|
      t.references :world, null: false, foreign_key: true
      t.string :name, null: false
      t.string :terrain, null: false
      t.jsonb :position, null: false, default: {}
      t.boolean :spawn_eligible, null: false, default: false
      t.boolean :is_hub, null: false, default: false
      t.timestamps

      t.index [ :world_id, :name ], unique: true
      t.index [ :world_id, :terrain ]
      t.index [ :world_id, :spawn_eligible ]
    end

    create_table :region_adjacencies do |t|
      t.references :region_a, null: false, foreign_key: { to_table: :regions }
      t.references :region_b, null: false, foreign_key: { to_table: :regions }
      t.timestamps

      t.index [ :region_a_id, :region_b_id ], unique: true
    end

    create_table :nodes do |t|
      t.references :region, null: false, foreign_key: true
      t.string :resource, null: false
      t.string :tier, null: false
      t.integer :base_rate, null: false
      t.bigint :owner_kingdom_id
      t.jsonb :garrison, null: false, default: {}
      t.boolean :is_home_hoard, null: false, default: false
      t.timestamps

      t.index :owner_kingdom_id
    end

    create_table :ruins do |t|
      t.references :region, null: false, foreign_key: true
      t.string :tier, null: false
      t.jsonb :garrison, null: false, default: {}
      t.jsonb :cache, null: false, default: {}
      t.bigint :claimed_by_kingdom_id
      t.datetime :claimed_at
      t.timestamps

      t.index :claimed_by_kingdom_id
    end
  end
end
