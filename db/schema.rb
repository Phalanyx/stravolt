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

ActiveRecord::Schema[8.1].define(version: 2026_01_25_143200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "users", force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.text "refresh_token"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "tesla_status", default: 0, null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["tesla_status"], name: "index_users_on_tesla_status"
  end

  create_table "vehicles", force: :cascade do |t|
    t.jsonb "cached_data", default: {}
    t.datetime "created_at", null: false
    t.string "display_name"
    t.boolean "telemetry_active", default: false
    t.jsonb "telemetry_config"
    t.datetime "telemetry_configured_at"
    t.boolean "telemetry_synced", default: false
    t.string "tesla_vehicle_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "vin", null: false
    t.index ["telemetry_active"], name: "index_vehicles_on_telemetry_active"
    t.index ["tesla_vehicle_id"], name: "index_vehicles_on_tesla_vehicle_id"
    t.index ["user_id", "tesla_vehicle_id"], name: "index_vehicles_on_user_id_and_tesla_vehicle_id", unique: true
    t.index ["user_id"], name: "index_vehicles_on_user_id"
    t.index ["vin"], name: "index_vehicles_on_vin"
  end

  add_foreign_key "vehicles", "users"
end
