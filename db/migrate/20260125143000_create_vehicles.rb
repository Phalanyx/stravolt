class CreateVehicles < ActiveRecord::Migration[7.0]
  def change
    create_table :vehicles do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :tesla_vehicle_id, null: false, index: true
      t.string :vin, null: false, index: true
      t.string :display_name
      t.text :cached_data, default: '{}'
      t.boolean :telemetry_active, default: false
      t.text :telemetry_config
      t.datetime :telemetry_configured_at
      t.boolean :telemetry_synced, default: false

      t.timestamps
    end

    add_index :vehicles, [:user_id, :tesla_vehicle_id], unique: true
    add_index :vehicles, :telemetry_active
  end
end
