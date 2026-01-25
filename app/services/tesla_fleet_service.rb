class TeslaFleetService
  include TeslaFleetErrors

  FLEET_API_URL = 'https://fleet-api.prd.na.vn.cloud.tesla.com'
  PROXY_URL = 'https://localhost:4443'

  def initialize(user)
    @user = user
  end

  # GET list of user's vehicles
  def fetch_vehicles
    make_request('/api/1/vehicles')
  end

  # GET comprehensive vehicle data
  def fetch_vehicle_data(vehicle_id)
    # Request specific endpoints including location_data
    endpoints = "charge_state;drive_state;location_data;vehicle_state"
    make_request("/api/1/vehicles/#{vehicle_id}/vehicle_data?endpoints=#{endpoints}")
  end

  # POST wake up vehicle
  def wake_up(vehicle_id)
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    # Use vehicle-command proxy for wake_up command
    ssl_options = {
      verify: false # Self-signed cert for local development
    }

    conn = Faraday.new(url: PROXY_URL, ssl: ssl_options) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.post("/api/1/vehicles/#{vehicle_id}/wake_up") do |req|
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

  # POST configure telemetry streaming for a vehicle
  def configure_telemetry(vehicle, config)
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    # Use vehicle-command proxy for telemetry configuration
    ssl_options = {
      verify: false # Self-signed cert for local development
    }

    conn = Faraday.new(url: PROXY_URL, ssl: ssl_options) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end

    # Note: This endpoint does NOT include VIN in the path
    # VINs are included in the config body
    response = conn.post("/api/1/vehicles/fleet_telemetry_config") do |req|
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

  # GET current telemetry configuration for a vehicle
  def get_telemetry_config(vehicle)
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    # Use vehicle-command proxy for telemetry configuration
    ssl_options = {
      verify: false # Self-signed cert for local development
    }

    conn = Faraday.new(url: PROXY_URL, ssl: ssl_options) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.get("/api/1/vehicles/#{vehicle.vin}/fleet_telemetry_config") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
    end

    if response.status == 200
      response.body['response']
    elsif response.status == 404
      nil # No telemetry config found
    else
      Rails.logger.error("Failed to get telemetry config for #{vehicle.vin}: #{response.status}")
      raise TeslaFleetError, "Failed to get telemetry config: #{response.status}"
    end
  rescue Faraday::Error => e
    Rails.logger.error("Error getting telemetry config: #{e.message}")
    raise ApiUnavailableError, "Tesla API is temporarily unavailable"
  end

  # DELETE telemetry configuration (stop streaming)
  def delete_telemetry_config(vehicle)
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    # Use vehicle-command proxy for telemetry configuration
    ssl_options = {
      verify: false # Self-signed cert for local development
    }

    conn = Faraday.new(url: PROXY_URL, ssl: ssl_options) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.delete("/api/1/vehicles/#{vehicle.vin}/fleet_telemetry_config") do |req|
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

  # GET telemetry errors for a specific vehicle
  def fetch_vehicle_telemetry_errors(vehicle)
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    # Use vehicle-command proxy for vehicle-specific telemetry errors
    ssl_options = {
      verify: false # Self-signed cert for local development
    }

    conn = Faraday.new(url: PROXY_URL, ssl: ssl_options) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.get("/api/1/vehicles/#{vehicle.vin}/fleet_telemetry_errors") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
    end

    if response.status == 200
      response.body
    elsif response.status == 404
      { 'response' => { 'errors' => [] } } # No errors found
    else
      Rails.logger.error("Failed to fetch telemetry errors for #{vehicle.vin}: #{response.status} - #{response.body}")
      raise TeslaFleetError, "Failed to fetch telemetry errors: #{response.status}"
    end
  rescue Faraday::Error => e
    Rails.logger.error("Error fetching telemetry errors: #{e.message}")
    raise ApiUnavailableError, "Tesla API is temporarily unavailable"
  end

  private

  def make_request(endpoint)
    token = @user.ensure_valid_tesla_token

    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    conn = Faraday.new(url: FLEET_API_URL) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.get(endpoint) do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
    end

    handle_response(response)
  rescue Faraday::Error => e
    Rails.logger.error("Tesla Fleet API error: #{e.message}")
    raise ApiUnavailableError, "Tesla API is temporarily unavailable"
  end

  def handle_response(response)
    case response.status
    when 200
      response.body['response']
    when 401
      raise TokenExpiredError, "Tesla token expired"
    when 404
      raise VehicleNotFoundError, "Vehicle not found"
    when 408
      raise VehicleAsleepError, "Vehicle is asleep"
    when 500..599
      raise ApiUnavailableError, "Tesla API server error"
    else
      raise TeslaFleetError, "Unexpected response: #{response.status}"
    end
  end
end
