class CreateWonders < ActiveRecord::Migration[8.1]
  def change
    create_table :wonders, id: :string do |t|
      t.references :kingdom, null: false, foreign_key: true, type: :string
      t.string :name, null: false
      t.string :status, null: false
      t.integer :hp, null: false, default: 0
      t.integer :target_hp, null: false, default: 10_000
      t.datetime :started_at, null: false
      t.datetime :construction_started_at
      t.datetime :consecration_at
      t.datetime :completed_at
      t.datetime :destroyed_at
      t.datetime :paused_until
      t.datetime :last_construction_at
      t.integer :pending_milestone_percent
      t.jsonb :milestones_paid, null: false, default: { "25" => false, "50" => false, "75" => false }
      t.jsonb :repaired_hp_by_phase, null: false, default: { "foundation" => 0, "construction" => 0, "consecration" => 0 }
      t.timestamps

      # At most one live Wonder per kingdom (foundation/construction/consecration).
      t.index :kingdom_id,
        unique: true,
        where: "status IN ('foundation','construction','consecration')",
        name: "index_wonders_on_kingdom_id_when_live"

      t.index [ :kingdom_id, :status ]
    end
  end
end
