class CreateServerFamily < ActiveRecord::Migration[8.1]
  def change
    create_table :servers do |t|
      t.citext :slug, null: false
      t.string :name, null: false
      t.references :owner_admin, null: false, foreign_key: { to_table: :admins }
      t.integer :max_concurrent_worlds, null: false, default: 2
      t.integer :max_worlds_per_account, null: false, default: 2
      t.timestamps
      t.index :slug, unique: true
    end

    create_table :server_adminships do |t|
      t.references :server, null: false, foreign_key: true
      t.references :admin,  null: false, foreign_key: true
      t.string :role, null: false, default: "admin"
      t.references :granted_by_admin, foreign_key: { to_table: :admins }
      t.datetime :joined_at, null: false
      t.timestamps
      t.index [ :server_id, :admin_id ], unique: true
    end

    create_table :server_accesses do |t|
      t.references :server, null: false, foreign_key: true
      t.string :kind, null: false
      t.citext :value, null: false
      t.timestamps
      t.index [ :server_id, :kind, :value ], unique: true
    end

    create_table :server_memberships do |t|
      t.references :server, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.datetime :joined_at, null: false
      t.timestamps
      t.index [ :server_id, :player_id ], unique: true
    end
  end
end
