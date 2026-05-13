# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_13_120002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "admins", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
  end

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "name"
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_api_keys_on_owner_type_and_owner_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "magic_links", force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "owner_id"
    t.string "owner_type", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "email"], name: "index_magic_links_on_owner_type_and_email"
    t.index ["token_digest"], name: "index_magic_links_on_token_digest", unique: true
  end

  create_table "nodes", force: :cascade do |t|
    t.integer "base_rate", null: false
    t.datetime "created_at", null: false
    t.jsonb "garrison", default: {}, null: false
    t.boolean "is_home_hoard", default: false, null: false
    t.bigint "owner_kingdom_id"
    t.bigint "region_id", null: false
    t.string "resource", null: false
    t.string "tier", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_kingdom_id"], name: "index_nodes_on_owner_kingdom_id"
    t.index ["region_id"], name: "index_nodes_on_region_id"
  end

  create_table "player_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "handle"
    t.bigint "player_id", null: false
    t.string "real_name"
    t.bigint "server_id", null: false
    t.jsonb "stats", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_player_profiles_on_player_id"
    t.index ["server_id", "handle"], name: "index_player_profiles_on_server_id_and_handle", unique: true, where: "(handle IS NOT NULL)"
    t.index ["server_id", "player_id"], name: "index_player_profiles_on_server_id_and_player_id", unique: true
    t.index ["server_id"], name: "index_player_profiles_on_server_id"
  end

  create_table "players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_players_on_email", unique: true
  end

  create_table "region_adjacencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "region_a_id", null: false
    t.bigint "region_b_id", null: false
    t.datetime "updated_at", null: false
    t.index ["region_a_id", "region_b_id"], name: "index_region_adjacencies_on_region_a_id_and_region_b_id", unique: true
    t.index ["region_a_id"], name: "index_region_adjacencies_on_region_a_id"
    t.index ["region_b_id"], name: "index_region_adjacencies_on_region_b_id"
  end

  create_table "regions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_hub", default: false, null: false
    t.string "name", null: false
    t.jsonb "position", default: {}, null: false
    t.boolean "spawn_eligible", default: false, null: false
    t.string "terrain", null: false
    t.datetime "updated_at", null: false
    t.bigint "world_id", null: false
    t.index ["world_id", "name"], name: "index_regions_on_world_id_and_name", unique: true
    t.index ["world_id", "spawn_eligible"], name: "index_regions_on_world_id_and_spawn_eligible"
    t.index ["world_id", "terrain"], name: "index_regions_on_world_id_and_terrain"
    t.index ["world_id"], name: "index_regions_on_world_id"
  end

  create_table "ruins", force: :cascade do |t|
    t.jsonb "cache", default: {}, null: false
    t.datetime "claimed_at"
    t.bigint "claimed_by_kingdom_id"
    t.datetime "created_at", null: false
    t.jsonb "garrison", default: {}, null: false
    t.bigint "region_id", null: false
    t.string "tier", null: false
    t.datetime "updated_at", null: false
    t.index ["claimed_by_kingdom_id"], name: "index_ruins_on_claimed_by_kingdom_id"
    t.index ["region_id"], name: "index_ruins_on_region_id"
  end

  create_table "server_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.bigint "server_id", null: false
    t.datetime "updated_at", null: false
    t.citext "value", null: false
    t.index ["server_id", "kind", "value"], name: "index_server_accesses_on_server_id_and_kind_and_value", unique: true
    t.index ["server_id"], name: "index_server_accesses_on_server_id"
  end

  create_table "server_adminships", force: :cascade do |t|
    t.bigint "admin_id", null: false
    t.datetime "created_at", null: false
    t.bigint "granted_by_admin_id"
    t.datetime "joined_at", null: false
    t.string "role", default: "admin", null: false
    t.bigint "server_id", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_server_adminships_on_admin_id"
    t.index ["granted_by_admin_id"], name: "index_server_adminships_on_granted_by_admin_id"
    t.index ["server_id", "admin_id"], name: "index_server_adminships_on_server_id_and_admin_id", unique: true
    t.index ["server_id"], name: "index_server_adminships_on_server_id"
  end

  create_table "server_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "joined_at", null: false
    t.bigint "player_id", null: false
    t.bigint "server_id", null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_server_memberships_on_player_id"
    t.index ["server_id", "player_id"], name: "index_server_memberships_on_server_id_and_player_id", unique: true
    t.index ["server_id"], name: "index_server_memberships_on_server_id"
  end

  create_table "servers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "max_concurrent_worlds", default: 2, null: false
    t.integer "max_worlds_per_account", default: 2, null: false
    t.string "name", null: false
    t.bigint "owner_admin_id", null: false
    t.citext "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_admin_id"], name: "index_servers_on_owner_admin_id"
    t.index ["slug"], name: "index_servers_on_slug", unique: true
  end

  create_table "world_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.bigint "invited_by_admin_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "world_id", null: false
    t.index ["invited_by_admin_id"], name: "index_world_invitations_on_invited_by_admin_id"
    t.index ["world_id", "email"], name: "index_world_invitations_on_world_id_and_email", unique: true
    t.index ["world_id"], name: "index_world_invitations_on_world_id"
  end

  create_table "worlds", force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "auto_cancel_after_hours", default: 168, null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "grace_closes_at"
    t.integer "min_players", null: false
    t.string "name", null: false
    t.string "seed", null: false
    t.bigint "server_id", null: false
    t.citext "slug", null: false
    t.string "status", default: "proposed", null: false
    t.datetime "t0_at", null: false
    t.datetime "updated_at", null: false
    t.string "wonder_name"
    t.index ["server_id", "slug"], name: "index_worlds_on_server_id_and_slug", unique: true
    t.index ["server_id", "status"], name: "index_worlds_on_server_id_and_status"
    t.index ["server_id"], name: "index_worlds_on_server_id"
    t.index ["status", "t0_at"], name: "index_worlds_on_status_and_t0_at"
  end

  add_foreign_key "nodes", "regions"
  add_foreign_key "player_profiles", "players"
  add_foreign_key "player_profiles", "servers"
  add_foreign_key "region_adjacencies", "regions", column: "region_a_id"
  add_foreign_key "region_adjacencies", "regions", column: "region_b_id"
  add_foreign_key "regions", "worlds"
  add_foreign_key "ruins", "regions"
  add_foreign_key "server_accesses", "servers"
  add_foreign_key "server_adminships", "admins"
  add_foreign_key "server_adminships", "admins", column: "granted_by_admin_id"
  add_foreign_key "server_adminships", "servers"
  add_foreign_key "server_memberships", "players"
  add_foreign_key "server_memberships", "servers"
  add_foreign_key "servers", "admins", column: "owner_admin_id"
  add_foreign_key "world_invitations", "admins", column: "invited_by_admin_id"
  add_foreign_key "world_invitations", "worlds"
  add_foreign_key "worlds", "servers"
end
