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

ActiveRecord::Schema[8.1].define(version: 2026_01_25_235939) do
  create_table "intervals", force: :cascade do |t|
    t.decimal "battery_percent", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.decimal "distance_from_previous_km", precision: 10, scale: 3
    t.string "gear"
    t.decimal "latitude", precision: 10, scale: 7, null: false
    t.decimal "longitude", precision: 10, scale: 7, null: false
    t.datetime "recorded_at", null: false
    t.decimal "speed_kmh", precision: 6, scale: 2, null: false
    t.bigint "trip_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recorded_at"], name: "index_intervals_on_recorded_at"
    t.index ["trip_id", "recorded_at"], name: "index_intervals_on_trip_and_recorded_at_unique", unique: true
    t.index ["trip_id", "recorded_at"], name: "index_intervals_on_trip_id_and_recorded_at"
    t.index ["trip_id"], name: "index_intervals_on_trip_id"
  end

  create_table "trips", force: :cascade do |t|
    t.decimal "avg_speed_kmh", precision: 6, scale: 2
    t.decimal "battery_consumed_percent", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.decimal "distance_km", precision: 10, scale: 2, default: "0.0"
    t.decimal "end_battery_percent", precision: 5, scale: 2
    t.decimal "end_latitude", precision: 10, scale: 7
    t.decimal "end_longitude", precision: 10, scale: 7
    t.datetime "ended_at"
    t.integer "intervals_count", default: 0
    t.decimal "max_speed_kmh", precision: 6, scale: 2
    t.decimal "start_battery_percent", precision: 5, scale: 2
    t.decimal "start_latitude", precision: 10, scale: 7
    t.decimal "start_longitude", precision: 10, scale: 7
    t.datetime "started_at", null: false
    t.string "trip_status", default: "in_progress", null: false
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["started_at"], name: "index_trips_on_started_at"
    t.index ["trip_status"], name: "index_trips_on_trip_status"
    t.index ["vehicle_id", "started_at"], name: "index_trips_on_vehicle_id_and_started_at"
    t.index ["vehicle_id", "trip_status"], name: "index_trips_on_vehicle_id_and_trip_status"
    t.index ["vehicle_id"], name: "index_trips_on_vehicle_id"
  end

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
    t.bigint "active_trip_id"
    t.text "cached_data", default: "{}"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.boolean "telemetry_active", default: false
    t.text "telemetry_config"
    t.datetime "telemetry_configured_at"
    t.boolean "telemetry_synced", default: false
    t.string "tesla_vehicle_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "vin", null: false
    t.index ["active_trip_id"], name: "index_vehicles_on_active_trip_id"
    t.index ["active_trip_id"], name: "index_vehicles_on_active_trip_id_partial", where: "(active_trip_id IS NOT NULL)"
    t.index ["telemetry_active"], name: "index_vehicles_on_telemetry_active"
    t.index ["tesla_vehicle_id"], name: "index_vehicles_on_tesla_vehicle_id"
    t.index ["user_id", "tesla_vehicle_id"], name: "index_vehicles_on_user_id_and_tesla_vehicle_id", unique: true
    t.index ["user_id"], name: "index_vehicles_on_user_id"
    t.index ["vin"], name: "index_vehicles_on_vin"
  end

  add_foreign_key "intervals", "trips"
  add_foreign_key "trips", "vehicles"
  add_foreign_key "vehicles", "trips", column: "active_trip_id"
  add_foreign_key "vehicles", "users"
end
