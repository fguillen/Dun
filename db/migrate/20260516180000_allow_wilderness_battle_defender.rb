class AllowWildernessBattleDefender < ActiveRecord::Migration[8.1]
  def change
    change_column_null :battles, :defender_kingdom_id, true
    change_column_null :battle_participants, :kingdom_id, true
  end
end
