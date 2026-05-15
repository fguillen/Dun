class CreateBattleParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :battle_participants, id: :string do |t|
      t.references :battle, null: false, foreign_key: true, type: :string
      t.references :kingdom, null: false, foreign_key: true, type: :string
      t.references :army, foreign_key: true, type: :string
      t.string :side, null: false
      t.jsonb :starting_composition, null: false, default: {}
      t.jsonb :ending_composition, null: false, default: {}
      t.jsonb :casualties, null: false, default: {}
      t.timestamps

      t.index [ :battle_id, :side ]
    end
  end
end
