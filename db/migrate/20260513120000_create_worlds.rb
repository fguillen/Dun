class CreateWorlds < ActiveRecord::Migration[8.1]
  def change
    create_table :worlds, id: :string do |t|
      t.references :server, null: false, foreign_key: true, type: :string
      t.string :name, null: false
      t.citext :slug, null: false
      t.string :seed, null: false
      t.string :status, null: false, default: "proposed"
      t.integer :min_players, null: false
      t.integer :auto_cancel_after_hours, null: false, default: 168
      t.datetime :t0_at, null: false
      t.datetime :grace_closes_at
      t.datetime :archived_at
      t.datetime :cancelled_at
      t.string :wonder_name
      t.timestamps

      t.index [ :server_id, :slug ], unique: true
      t.index [ :server_id, :status ]
      t.index [ :status, :t0_at ]
    end
  end
end
