class CreateTrips < ActiveRecord::Migration[8.1]
  def change
    create_table :trips do |t|
      t.references :vehicle, null: false, foreign_key: true, index: true

      # Trip lifecycle
      t.datetime :started_at, null: false
      t.datetime :ended_at

      # Geographic data
      t.decimal :start_latitude, precision: 10, scale: 7
      t.decimal :start_longitude, precision: 10, scale: 7
      t.decimal :end_latitude, precision: 10, scale: 7
      t.decimal :end_longitude, precision: 10, scale: 7

      # Trip metrics
      t.decimal :distance_km, precision: 10, scale: 2, default: 0.0
      t.decimal :avg_speed_kmh, precision: 6, scale: 2
      t.decimal :max_speed_kmh, precision: 6, scale: 2

      # Battery tracking
      t.decimal :start_battery_percent, precision: 5, scale: 2
      t.decimal :end_battery_percent, precision: 5, scale: 2
      t.decimal :battery_consumed_percent, precision: 5, scale: 2

      # Trip status
      t.string :trip_status, default: 'in_progress', null: false
      t.integer :intervals_count, default: 0

      t.timestamps
    end

    add_index :trips, :started_at
    add_index :trips, :trip_status
    add_index :trips, [:vehicle_id, :trip_status]
    add_index :trips, [:vehicle_id, :started_at]
  end
end
