class CreateKingdoms < ActiveRecord::Migration[8.1]
  DEFAULT_STOCKPILES = { "gold" => 0, "wood" => 0, "stone" => 0, "iron" => 0 }.freeze

  def change
    create_table :kingdoms, id: :string do |t|
      t.references :world, null: false, foreign_key: true, type: :string
      t.references :player_profile, null: false, foreign_key: true, type: :string
      t.references :home_region, foreign_key: { to_table: :regions }, type: :string
      t.jsonb :stockpiles, null: false, default: DEFAULT_STOCKPILES
      t.jsonb :metadata, null: false, default: {}
      t.datetime :joined_at, null: false
      t.datetime :eliminated_at
      t.timestamps

      t.index [ :world_id, :player_profile_id ], unique: true
    end

    add_foreign_key :worlds, :kingdoms, column: :winner_kingdom_id if column_exists?(:worlds, :winner_kingdom_id)
    add_reference :worlds, :winner_kingdom, foreign_key: { to_table: :kingdoms }, type: :string unless column_exists?(:worlds, :winner_kingdom_id)
  end
end
