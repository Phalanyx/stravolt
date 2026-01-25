class RemoveVehicleColumnsFromUsers < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :tesla_vehicle_id, :string if column_exists?(:users, :tesla_vehicle_id)
    remove_column :users, :tesla_vehicle_vin, :string if column_exists?(:users, :tesla_vehicle_vin)
    remove_column :users, :tesla_vehicle_name, :string if column_exists?(:users, :tesla_vehicle_name)
    remove_column :users, :tesla_vehicle_cached_data, :jsonb if column_exists?(:users, :tesla_vehicle_cached_data)
  end
end
