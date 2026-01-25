class TelemetryConfigBuilder
  def self.build_config(vehicle)
    {
      "vins" => [vehicle.vin], # VINs array is required for the create endpoint
      "config" => {
        "hostname" => "telemetry.stravolt.com",
        "port" => 443,
        "ca" => ENV['TELEMETRY_CHAIN'], # Certificate chain from environment
        "fields" => {
          "Soc" => { "interval_seconds" => 30 }
        }
      }
    }
  end
end
