class CreateIntervals < ActiveRecord::Migration[8.1]
  def change
    create_table :intervals do |t|
      t.references :trip, null: false, foreign_key: true, index: true

      t.datetime :recorded_at, null: false

      # Location data
      t.decimal :latitude, precision: 10, scale: 7, null: false
      t.decimal :longitude, precision: 10, scale: 7, null: false

      # Vehicle metrics
      t.decimal :speed_kmh, precision: 6, scale: 2, null: false
      t.decimal :battery_percent, precision: 5, scale: 2

      t.string :gear
      t.decimal :distance_from_previous_km, precision: 10, scale: 3

      t.timestamps
    end

    add_index :intervals, :recorded_at
    add_index :intervals, [:trip_id, :recorded_at]
    add_index :intervals, [:trip_id, :recorded_at], unique: true,
              name: 'index_intervals_on_trip_and_recorded_at_unique'
  end
end
