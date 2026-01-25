class TelemetryProxyClient
  include TeslaFleetErrors

  PROXY_URL = 'https://localhost:4443'

  def initialize(user)
    @user = user
  end

  # POST configure telemetry streaming for a vehicle
  def configure(vehicle, config)
    token = ensure_token

    response = connection.post("/api/1/vehicles/fleet_telemetry_config") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
      req.body = config.to_json
    end

    if response.status == 200
      Rails.logger.info("Telemetry configured for vehicle #{vehicle.vin}")
      response.body
    else
      Rails.logger.error("Failed to configure telemetry for #{vehicle.vin}: #{response.status} - #{response.body}")
      raise TeslaFleetError, "Failed to configure telemetry: #{response.status}"
    end
  rescue Faraday::Error => e
    Rails.logger.error("Error configuring telemetry: #{e.message}")
    raise ApiUnavailableError, "Tesla API is temporarily unavailable"
  end

  # DELETE telemetry configuration (stop streaming)
  def delete(vehicle)
    token = ensure_token

    response = connection.delete("/api/1/vehicles/#{vehicle.vin}/fleet_telemetry_config") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
    end

    if response.status == 200
      Rails.logger.info("Telemetry deleted for vehicle #{vehicle.vin}")
      true
    else
      Rails.logger.error("Failed to delete telemetry for #{vehicle.vin}: #{response.status}")
      false
    end
  rescue Faraday::Error => e
    Rails.logger.error("Error deleting telemetry config: #{e.message}")
    false
  end

  # GET current telemetry configuration for a vehicle
  def get_config(vehicle)
    token = ensure_token

    response = connection.get("/api/1/vehicles/#{vehicle.vin}/fleet_telemetry_config") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
    end

    if response.status == 200
      response.body['response']
    elsif response.status == 404
      nil
    else
      Rails.logger.error("Failed to get telemetry config for #{vehicle.vin}: #{response.status}")
      raise TeslaFleetError, "Failed to get telemetry config: #{response.status}"
    end
  rescue Faraday::Error => e
    Rails.logger.error("Error getting telemetry config: #{e.message}")
    raise ApiUnavailableError, "Tesla API is temporarily unavailable"
  end

  # GET telemetry errors for a specific vehicle
  def errors(vehicle)
    token = ensure_token

    response = connection.get("/api/1/vehicles/#{vehicle.vin}/fleet_telemetry_errors") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
    end

    if response.status == 200
      response.body
    elsif response.status == 404
      { 'response' => { 'errors' => [] } }
    else
      Rails.logger.error("Failed to fetch telemetry errors for #{vehicle.vin}: #{response.status} - #{response.body}")
      raise TeslaFleetError, "Failed to fetch telemetry errors: #{response.status}"
    end
  rescue Faraday::Error => e
    Rails.logger.error("Error fetching telemetry errors: #{e.message}")
    raise ApiUnavailableError, "Tesla API is temporarily unavailable"
  end

  # POST wake up vehicle
  def wake_up(vehicle_id)
    token = ensure_token

    response = connection.post("/api/1/vehicles/#{vehicle_id}/wake_up") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
    end

    if response.status == 200
      Rails.logger.info("Vehicle #{vehicle_id} wake up command sent successfully")
      true
    else
      Rails.logger.warn("Failed to wake vehicle #{vehicle_id}: #{response.status}")
      false
    end
  rescue Faraday::Error => e
    Rails.logger.error("Error waking vehicle: #{e.message}")
    false
  end

  private

  def connection
    @connection ||= Faraday.new(url: PROXY_URL, ssl: { verify: false }) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def ensure_token
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?
    token
  end
end
