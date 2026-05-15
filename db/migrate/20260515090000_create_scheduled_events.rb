class CreateScheduledEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_events, id: :string do |t|
      t.references :world, null: false, foreign_key: true, type: :string
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :fire_at, null: false
      t.datetime :processed_at
      t.timestamps

      t.index [ :fire_at, :id ],
        name: "index_scheduled_events_pending_by_fire_at",
        where: "processed_at IS NULL"
      t.index [ :world_id, :kind ]
      t.index :processed_at
    end
  end
end
