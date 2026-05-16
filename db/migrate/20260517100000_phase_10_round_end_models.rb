class Phase10RoundEndModels < ActiveRecord::Migration[8.1]
  def change
    create_table :round_archives, id: :string do |t|
      t.references :world, null: false, foreign_key: true, type: :string, index: { unique: true }
      t.references :winner_kingdom, null: true, foreign_key: { to_table: :kingdoms }, type: :string
      t.string :wonder_name
      t.jsonb :frozen_state, null: false, default: {}
      t.datetime :ended_at, null: false
      t.timestamps
    end

    create_table :player_profile_stats, id: :string do |t|
      t.references :player_profile, null: false, foreign_key: true, type: :string, index: { unique: true }
      t.integer :rounds_played,      null: false, default: 0
      t.integer :rounds_won,         null: false, default: 0
      t.integer :wonders_completed,  null: false, default: 0
      t.integer :wonders_destroyed,  null: false, default: 0
      t.integer :peak_nodes,         null: false, default: 0
      t.integer :raids_launched,     null: false, default: 0
      t.integer :raids_defended,     null: false, default: 0
      t.integer :raids_won_offense,  null: false, default: 0
      t.integer :raids_won_defense,  null: false, default: 0
      t.bigint  :resources_looted,   null: false, default: 0
      t.timestamps
      t.index :rounds_won
      t.index :wonders_destroyed
      t.index :peak_nodes
      t.index :rounds_played
    end

    create_table :player_titles, id: :string do |t|
      t.references :player_profile, null: false, foreign_key: true, type: :string
      t.references :world, null: false, foreign_key: true, type: :string
      t.string :kind, null: false, default: "champion"
      t.datetime :awarded_at, null: false
      t.timestamps
      t.index [ :player_profile_id, :world_id, :kind ], unique: true, name: "index_player_titles_unique"
    end

    create_table :leaderboard_snapshots, id: :string do |t|
      t.references :server, null: false, foreign_key: true, type: :string
      t.string :kind, null: false
      t.datetime :snapshot_at, null: false
      t.jsonb :entries, null: false, default: []
      t.timestamps
      t.index [ :server_id, :kind ], unique: true
    end

    create_table :retired_handles, id: :string do |t|
      t.references :server, null: false, foreign_key: true, type: :string
      t.citext :handle_lower, null: false
      t.datetime :freed_at, null: false
      t.timestamps
      t.index [ :server_id, :handle_lower ], unique: true
    end

    add_column :players, :deleted_at, :datetime
    add_index :players, :deleted_at

    add_column :kingdoms, :peak_nodes, :integer, null: false, default: 0

    remove_column :player_profiles, :stats, :jsonb, null: false, default: {}
  end
end
