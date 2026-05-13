class CreateWorldInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :world_invitations, id: :string do |t|
      t.references :world, null: false, foreign_key: true, type: :string
      t.citext :email, null: false
      t.references :invited_by_admin, null: false, foreign_key: { to_table: :admins }, type: :string
      t.timestamps

      t.index [ :world_id, :email ], unique: true
    end
  end
end
