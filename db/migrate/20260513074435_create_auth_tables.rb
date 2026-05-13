class CreateAuthTables < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.citext :email, null: false
      t.string :name, null: false
      t.timestamps
      t.index :email, unique: true
    end

    create_table :admins do |t|
      t.citext :email, null: false
      t.string :name, null: false
      t.timestamps
      t.index :email, unique: true
    end

    create_table :magic_links do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id
      t.citext :email, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
      t.index :token_digest, unique: true
      t.index [ :owner_type, :email ]
    end

    create_table :api_keys do |t|
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.string :name
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
      t.index :token_digest, unique: true
      t.index [ :owner_type, :owner_id ]
    end
  end
end
