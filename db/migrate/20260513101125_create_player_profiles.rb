class CreatePlayerProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :player_profiles, id: :string do |t|
      t.references :server, null: false, foreign_key: true, type: :string
      t.references :player, null: false, foreign_key: true, type: :string
      t.citext :handle
      t.string :real_name
      t.jsonb :stats, null: false, default: {}
      t.timestamps
      t.index [ :server_id, :handle ], unique: true, where: "handle IS NOT NULL"
      t.index [ :server_id, :player_id ], unique: true
    end
  end
end
