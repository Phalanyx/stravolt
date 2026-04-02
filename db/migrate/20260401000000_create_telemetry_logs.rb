class CreateTelemetryLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :telemetry_logs do |t|
      t.string :vin, null: false
      t.jsonb :metadata
      t.jsonb :data

      t.timestamps
    end

    add_index :telemetry_logs, :vin
  end
end
