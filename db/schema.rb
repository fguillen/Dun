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

ActiveRecord::Schema[8.1].define(version: 2026_05_16_200001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "admins", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
  end

  create_table "api_keys", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "name"
    t.string "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_api_keys_on_owner_type_and_owner_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "armies", id: :string, force: :cascade do |t|
    t.jsonb "composition", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "kingdom_id", null: false
    t.string "location_region_id", null: false
    t.string "name", null: false
    t.string "status", default: "home", null: false
    t.datetime "updated_at", null: false
    t.index ["kingdom_id", "name"], name: "index_armies_on_kingdom_id_and_name", unique: true
    t.index ["kingdom_id", "status"], name: "index_armies_on_kingdom_id_and_status"
    t.index ["kingdom_id"], name: "index_armies_on_kingdom_id"
    t.index ["location_region_id"], name: "index_armies_on_location_region_id"
  end

  create_table "battle_participants", id: :string, force: :cascade do |t|
    t.string "army_id"
    t.string "battle_id", null: false
    t.jsonb "casualties", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "ending_composition", default: {}, null: false
    t.string "kingdom_id"
    t.string "side", null: false
    t.jsonb "starting_composition", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["army_id"], name: "index_battle_participants_on_army_id"
    t.index ["battle_id", "side"], name: "index_battle_participants_on_battle_id_and_side"
    t.index ["battle_id"], name: "index_battle_participants_on_battle_id"
    t.index ["kingdom_id"], name: "index_battle_participants_on_kingdom_id"
  end

  create_table "battles", id: :string, force: :cascade do |t|
    t.string "attacker_kingdom_id", null: false
    t.datetime "created_at", null: false
    t.string "defender_kingdom_id"
    t.datetime "ended_at", null: false
    t.jsonb "log", default: [], null: false
    t.jsonb "loot", default: {}, null: false
    t.string "march_order_id"
    t.string "outcome", null: false
    t.string "region_id", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.string "variance_seed"
    t.string "world_id", null: false
    t.index ["attacker_kingdom_id", "ended_at"], name: "index_battles_on_attacker_kingdom_id_and_ended_at"
    t.index ["attacker_kingdom_id"], name: "index_battles_on_attacker_kingdom_id"
    t.index ["defender_kingdom_id", "ended_at"], name: "index_battles_on_defender_kingdom_id_and_ended_at"
    t.index ["defender_kingdom_id"], name: "index_battles_on_defender_kingdom_id"
    t.index ["march_order_id"], name: "index_battles_on_march_order_id"
    t.index ["region_id"], name: "index_battles_on_region_id"
    t.index ["world_id", "ended_at"], name: "index_battles_on_world_id_and_ended_at"
    t.index ["world_id"], name: "index_battles_on_world_id"
  end

  create_table "build_orders", id: :string, force: :cascade do |t|
    t.string "building_id", null: false
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "completes_at", null: false
    t.datetime "created_at", null: false
    t.string "kingdom_id", null: false
    t.datetime "started_at", null: false
    t.integer "target_level", null: false
    t.datetime "updated_at", null: false
    t.index ["building_id"], name: "index_build_orders_on_building_id"
    t.index ["completes_at"], name: "index_build_orders_on_completes_at"
    t.index ["kingdom_id"], name: "index_build_orders_on_kingdom_id"
    t.index ["kingdom_id"], name: "index_build_orders_on_kingdom_id_unresolved", where: "((completed_at IS NULL) AND (cancelled_at IS NULL))"
  end

  create_table "buildings", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "kingdom_id", null: false
    t.integer "level", default: 0, null: false
    t.jsonb "position"
    t.datetime "updated_at", null: false
    t.integer "wall_hp"
    t.index ["kingdom_id", "kind"], name: "index_buildings_on_kingdom_id_and_kind", unique: true
    t.index ["kingdom_id"], name: "index_buildings_on_kingdom_id"
  end

  create_table "caravans", id: :string, force: :cascade do |t|
    t.datetime "arrives_at", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "destination_region_id", null: false
    t.datetime "dispatched_at", null: false
    t.string "escort_army_id"
    t.jsonb "escort_units", default: {}, null: false
    t.datetime "intercepted_at"
    t.string "origin_region_id", null: false
    t.string "outbound_march_order_id"
    t.jsonb "payload", default: {}, null: false
    t.string "receiver_kingdom_id", null: false
    t.string "return_march_order_id"
    t.string "sender_kingdom_id", null: false
    t.string "status", default: "in_transit", null: false
    t.datetime "updated_at", null: false
    t.string "world_id", null: false
    t.index ["destination_region_id"], name: "index_caravans_on_destination_region_id"
    t.index ["escort_army_id"], name: "index_caravans_on_escort_army_id"
    t.index ["origin_region_id"], name: "index_caravans_on_origin_region_id"
    t.index ["outbound_march_order_id"], name: "index_caravans_on_outbound_march_order_id", unique: true
    t.index ["receiver_kingdom_id"], name: "index_caravans_on_receiver_kingdom_id"
    t.index ["return_march_order_id"], name: "index_caravans_on_return_march_order_id", unique: true
    t.index ["sender_kingdom_id"], name: "index_caravans_on_sender_kingdom_id"
    t.index ["world_id", "status"], name: "index_caravans_on_world_id_and_status"
    t.index ["world_id"], name: "index_caravans_on_world_id"
  end

  create_table "data_migrations", primary_key: "version", id: :string, force: :cascade do |t|
  end

  create_table "kingdoms", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "eliminated_at"
    t.string "home_region_id"
    t.datetime "joined_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "player_profile_id", null: false
    t.jsonb "stockpiles", default: {"gold" => 0, "iron" => 0, "wood" => 0, "stone" => 0}, null: false
    t.datetime "updated_at", null: false
    t.string "world_id", null: false
    t.index ["home_region_id"], name: "index_kingdoms_on_home_region_id"
    t.index ["player_profile_id"], name: "index_kingdoms_on_player_profile_id"
    t.index ["world_id", "player_profile_id"], name: "index_kingdoms_on_world_id_and_player_profile_id", unique: true
    t.index ["world_id"], name: "index_kingdoms_on_world_id"
  end

  create_table "magic_links", id: :string, force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.datetime "expires_at", null: false
    t.string "owner_id"
    t.string "owner_type", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "email"], name: "index_magic_links_on_owner_type_and_email"
    t.index ["token_digest"], name: "index_magic_links_on_token_digest", unique: true
  end

  create_table "march_orders", id: :string, force: :cascade do |t|
    t.string "army_id", null: false
    t.datetime "arrived_at"
    t.datetime "arrives_at", null: false
    t.jsonb "cargo"
    t.datetime "created_at", null: false
    t.datetime "dispatched_at", null: false
    t.jsonb "escort_units"
    t.string "intent", null: false
    t.string "origin_region_id", null: false
    t.jsonb "path", default: [], null: false
    t.datetime "recalled_at"
    t.string "target_region_id", null: false
    t.datetime "updated_at", null: false
    t.index ["army_id"], name: "index_march_orders_on_army_id"
    t.index ["army_id"], name: "index_march_orders_on_army_id_active", where: "((arrived_at IS NULL) AND (recalled_at IS NULL))"
    t.index ["arrives_at"], name: "index_march_orders_on_arrives_at"
    t.index ["origin_region_id"], name: "index_march_orders_on_origin_region_id"
    t.index ["target_region_id", "arrives_at"], name: "index_march_orders_by_target_arrival"
    t.index ["target_region_id"], name: "index_march_orders_on_target_region_id"
  end

  create_table "nodes", id: :string, force: :cascade do |t|
    t.integer "base_rate", null: false
    t.datetime "created_at", null: false
    t.jsonb "garrison", default: {}, null: false
    t.boolean "is_home_hoard", default: false, null: false
    t.string "owner_kingdom_id"
    t.string "region_id", null: false
    t.string "resource", null: false
    t.string "tier", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_kingdom_id"], name: "index_nodes_on_owner_kingdom_id"
    t.index ["region_id"], name: "index_nodes_on_region_id"
  end

  create_table "player_profiles", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "handle"
    t.string "player_id", null: false
    t.string "real_name"
    t.string "server_id", null: false
    t.jsonb "stats", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_player_profiles_on_player_id"
    t.index ["server_id", "handle"], name: "index_player_profiles_on_server_id_and_handle", unique: true, where: "(handle IS NOT NULL)"
    t.index ["server_id", "player_id"], name: "index_player_profiles_on_server_id_and_player_id", unique: true
    t.index ["server_id"], name: "index_player_profiles_on_server_id"
  end

  create_table "players", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_players_on_email", unique: true
  end

  create_table "region_adjacencies", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "region_a_id", null: false
    t.string "region_b_id", null: false
    t.datetime "updated_at", null: false
    t.index ["region_a_id", "region_b_id"], name: "index_region_adjacencies_on_region_a_id_and_region_b_id", unique: true
    t.index ["region_a_id"], name: "index_region_adjacencies_on_region_a_id"
    t.index ["region_b_id"], name: "index_region_adjacencies_on_region_b_id"
  end

  create_table "regions", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_hub", default: false, null: false
    t.string "name", null: false
    t.jsonb "position", default: {}, null: false
    t.boolean "spawn_eligible", default: false, null: false
    t.string "terrain", null: false
    t.datetime "updated_at", null: false
    t.string "world_id", null: false
    t.index ["world_id", "name"], name: "index_regions_on_world_id_and_name", unique: true
    t.index ["world_id", "spawn_eligible"], name: "index_regions_on_world_id_and_spawn_eligible"
    t.index ["world_id", "terrain"], name: "index_regions_on_world_id_and_terrain"
    t.index ["world_id"], name: "index_regions_on_world_id"
  end

  create_table "ruins", id: :string, force: :cascade do |t|
    t.jsonb "cache", default: {}, null: false
    t.datetime "claimed_at"
    t.string "claimed_by_kingdom_id"
    t.datetime "created_at", null: false
    t.jsonb "garrison", default: {}, null: false
    t.string "region_id", null: false
    t.string "tier", null: false
    t.datetime "updated_at", null: false
    t.index ["claimed_by_kingdom_id"], name: "index_ruins_on_claimed_by_kingdom_id"
    t.index ["region_id"], name: "index_ruins_on_region_id"
  end

  create_table "scheduled_events", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fire_at", null: false
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.datetime "updated_at", null: false
    t.string "world_id", null: false
    t.index ["fire_at", "id"], name: "index_scheduled_events_pending_by_fire_at", where: "(processed_at IS NULL)"
    t.index ["processed_at"], name: "index_scheduled_events_on_processed_at"
    t.index ["world_id", "kind"], name: "index_scheduled_events_on_world_id_and_kind"
    t.index ["world_id"], name: "index_scheduled_events_on_world_id"
  end

  create_table "server_accesses", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "server_id", null: false
    t.datetime "updated_at", null: false
    t.citext "value", null: false
    t.index ["server_id", "kind", "value"], name: "index_server_accesses_on_server_id_and_kind_and_value", unique: true
    t.index ["server_id"], name: "index_server_accesses_on_server_id"
  end

  create_table "server_adminships", id: :string, force: :cascade do |t|
    t.string "admin_id", null: false
    t.datetime "created_at", null: false
    t.string "granted_by_admin_id"
    t.datetime "joined_at", null: false
    t.string "role", default: "admin", null: false
    t.string "server_id", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_server_adminships_on_admin_id"
    t.index ["granted_by_admin_id"], name: "index_server_adminships_on_granted_by_admin_id"
    t.index ["server_id", "admin_id"], name: "index_server_adminships_on_server_id_and_admin_id", unique: true
    t.index ["server_id"], name: "index_server_adminships_on_server_id"
  end

  create_table "server_memberships", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "joined_at", null: false
    t.string "player_id", null: false
    t.string "server_id", null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_server_memberships_on_player_id"
    t.index ["server_id", "player_id"], name: "index_server_memberships_on_server_id_and_player_id", unique: true
    t.index ["server_id"], name: "index_server_memberships_on_server_id"
  end

  create_table "servers", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "max_concurrent_worlds", default: 2, null: false
    t.integer "max_worlds_per_account", default: 2, null: false
    t.string "name", null: false
    t.string "owner_admin_id", null: false
    t.citext "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_admin_id"], name: "index_servers_on_owner_admin_id"
    t.index ["slug"], name: "index_servers_on_slug", unique: true
  end

  create_table "trade_ledger_entries", id: :string, force: :cascade do |t|
    t.bigint "amount", null: false
    t.string "attacker_handle"
    t.string "caravan_id", null: false
    t.datetime "created_at", null: false
    t.string "receiver_handle_at_send", null: false
    t.datetime "recorded_at", null: false
    t.string "resource", null: false
    t.string "sender_handle_at_send", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.string "world_id", null: false
    t.index ["caravan_id", "resource"], name: "index_trade_ledger_entries_on_caravan_id_and_resource", unique: true
    t.index ["caravan_id"], name: "index_trade_ledger_entries_on_caravan_id"
    t.index ["world_id", "attacker_handle"], name: "index_trade_ledger_entries_on_world_id_and_attacker_handle"
    t.index ["world_id", "receiver_handle_at_send"], name: "idx_on_world_id_receiver_handle_at_send_56e04c7fda"
    t.index ["world_id", "recorded_at"], name: "index_trade_ledger_entries_on_world_id_and_recorded_at"
    t.index ["world_id", "sender_handle_at_send"], name: "idx_on_world_id_sender_handle_at_send_d6c405a107"
    t.index ["world_id"], name: "index_trade_ledger_entries_on_world_id"
  end

  create_table "training_orders", id: :string, force: :cascade do |t|
    t.string "building_id", null: false
    t.string "building_kind", null: false
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "completes_at", null: false
    t.integer "count", null: false
    t.datetime "created_at", null: false
    t.string "kingdom_id", null: false
    t.datetime "started_at", null: false
    t.string "unit", null: false
    t.datetime "updated_at", null: false
    t.index ["building_id"], name: "index_training_orders_on_building_id"
    t.index ["building_id"], name: "index_training_orders_on_building_id_unresolved", where: "((completed_at IS NULL) AND (cancelled_at IS NULL))"
    t.index ["completes_at"], name: "index_training_orders_on_completes_at"
    t.index ["kingdom_id"], name: "index_training_orders_on_kingdom_id"
    t.index ["kingdom_id"], name: "index_training_orders_on_kingdom_id_unresolved", where: "((completed_at IS NULL) AND (cancelled_at IS NULL))"
  end

  create_table "world_invitations", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "invited_by_admin_id", null: false
    t.datetime "updated_at", null: false
    t.string "world_id", null: false
    t.index ["invited_by_admin_id"], name: "index_world_invitations_on_invited_by_admin_id"
    t.index ["world_id", "email"], name: "index_world_invitations_on_world_id_and_email", unique: true
    t.index ["world_id"], name: "index_world_invitations_on_world_id"
  end

  create_table "worlds", id: :string, force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "auto_cancel_after_hours", default: 168, null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "grace_closes_at"
    t.integer "min_players", null: false
    t.string "name", null: false
    t.string "seed", null: false
    t.string "server_id", null: false
    t.citext "slug", null: false
    t.string "status", default: "proposed", null: false
    t.datetime "t0_at", null: false
    t.datetime "updated_at", null: false
    t.string "winner_kingdom_id"
    t.string "wonder_name"
    t.index ["server_id", "slug"], name: "index_worlds_on_server_id_and_slug", unique: true
    t.index ["server_id", "status"], name: "index_worlds_on_server_id_and_status"
    t.index ["server_id"], name: "index_worlds_on_server_id"
    t.index ["status", "t0_at"], name: "index_worlds_on_status_and_t0_at"
    t.index ["winner_kingdom_id"], name: "index_worlds_on_winner_kingdom_id"
  end

  add_foreign_key "armies", "kingdoms"
  add_foreign_key "armies", "regions", column: "location_region_id"
  add_foreign_key "battle_participants", "armies"
  add_foreign_key "battle_participants", "battles"
  add_foreign_key "battle_participants", "kingdoms"
  add_foreign_key "battles", "kingdoms", column: "attacker_kingdom_id"
  add_foreign_key "battles", "kingdoms", column: "defender_kingdom_id"
  add_foreign_key "battles", "march_orders"
  add_foreign_key "battles", "regions"
  add_foreign_key "battles", "worlds"
  add_foreign_key "build_orders", "buildings"
  add_foreign_key "build_orders", "kingdoms"
  add_foreign_key "buildings", "kingdoms"
  add_foreign_key "caravans", "armies", column: "escort_army_id", on_delete: :nullify
  add_foreign_key "caravans", "kingdoms", column: "receiver_kingdom_id"
  add_foreign_key "caravans", "kingdoms", column: "sender_kingdom_id"
  add_foreign_key "caravans", "march_orders", column: "outbound_march_order_id", on_delete: :nullify
  add_foreign_key "caravans", "march_orders", column: "return_march_order_id", on_delete: :nullify
  add_foreign_key "caravans", "regions", column: "destination_region_id"
  add_foreign_key "caravans", "regions", column: "origin_region_id"
  add_foreign_key "caravans", "worlds"
  add_foreign_key "kingdoms", "player_profiles"
  add_foreign_key "kingdoms", "regions", column: "home_region_id"
  add_foreign_key "kingdoms", "worlds"
  add_foreign_key "march_orders", "armies"
  add_foreign_key "march_orders", "regions", column: "origin_region_id"
  add_foreign_key "march_orders", "regions", column: "target_region_id"
  add_foreign_key "nodes", "regions"
  add_foreign_key "player_profiles", "players"
  add_foreign_key "player_profiles", "servers"
  add_foreign_key "region_adjacencies", "regions", column: "region_a_id"
  add_foreign_key "region_adjacencies", "regions", column: "region_b_id"
  add_foreign_key "regions", "worlds"
  add_foreign_key "ruins", "regions"
  add_foreign_key "scheduled_events", "worlds"
  add_foreign_key "server_accesses", "servers"
  add_foreign_key "server_adminships", "admins"
  add_foreign_key "server_adminships", "admins", column: "granted_by_admin_id"
  add_foreign_key "server_adminships", "servers"
  add_foreign_key "server_memberships", "players"
  add_foreign_key "server_memberships", "servers"
  add_foreign_key "servers", "admins", column: "owner_admin_id"
  add_foreign_key "trade_ledger_entries", "caravans"
  add_foreign_key "trade_ledger_entries", "worlds"
  add_foreign_key "training_orders", "buildings"
  add_foreign_key "training_orders", "kingdoms"
  add_foreign_key "world_invitations", "admins", column: "invited_by_admin_id"
  add_foreign_key "world_invitations", "worlds"
  add_foreign_key "worlds", "kingdoms", column: "winner_kingdom_id"
  add_foreign_key "worlds", "servers"
end
