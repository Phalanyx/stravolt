class TelemetryConfigBuilder
  def self.build_config(vehicle)
    {
      "vins" => [vehicle.vin], # VINs array is required for the create endpoint
      "config" => {
        "hostname" => "telemetry.stravolt.com",
        "port" => 443,
        "ca" => ENV['TELEMETRY_CHAIN'], # Certificate chain from environment
        "fields" => {
          # Gear state (Drive/Park/Reverse/Neutral) - triggers on state changes
          "Gear" => { "interval_seconds" => 1 },

          # Location updates when vehicle moves
          "Location" => { "interval_seconds" => 5 },

          # Battery state of charge - only sends when value changes
          "Soc" => { "interval_seconds" => 60 },

          # Vehicle speed to track movement
          "VehicleSpeed" => { "interval_seconds" => 5 }
        }
      }
    }
  end
end
