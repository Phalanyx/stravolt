class AddTeslaVehicleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tesla_vehicle_id, :string
    add_column :users, :tesla_vehicle_vin, :string
    add_column :users, :tesla_vehicle_name, :string
    add_column :users, :tesla_vehicle_cached_data, :jsonb
    add_index :users, :tesla_vehicle_id
  end
end
