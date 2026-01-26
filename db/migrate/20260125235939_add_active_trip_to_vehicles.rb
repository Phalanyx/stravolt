class AddActiveTripToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_reference :vehicles, :active_trip, foreign_key: { to_table: :trips }, index: false
    add_index :vehicles, :active_trip_id
    add_index :vehicles, :active_trip_id, where: "active_trip_id IS NOT NULL",
              name: 'index_vehicles_on_active_trip_id_partial'
  end
end
