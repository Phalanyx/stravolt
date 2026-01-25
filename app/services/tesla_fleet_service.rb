class TeslaFleetService
  include TeslaFleetErrors

  FLEET_API_URL = 'https://fleet-api.prd.na.vn.cloud.tesla.com'
  CACHE_TTL = 30.seconds

  def initialize(user)
    @user = user
  end

  # GET list of user's vehicles
  def fetch_vehicles
    with_caching('tesla_vehicles', CACHE_TTL) do
      make_request('/api/1/vehicles')
    end
  end

  # GET comprehensive vehicle data
  def fetch_vehicle_data(vehicle_id)
    with_caching("tesla_vehicle_#{vehicle_id}", CACHE_TTL) do
      # Request specific endpoints including location_data
      endpoints = "charge_state;drive_state;location_data;vehicle_state"
      data = make_request("/api/1/vehicles/#{vehicle_id}/vehicle_data?endpoints=#{endpoints}")

      # Cache to database for offline fallback
      @user.update(tesla_vehicle_cached_data: data)

      data
    end
  rescue TeslaFleetError => e
    # Return cached data if available
    if @user.tesla_vehicle_cached_data.present?
      Rails.logger.info("Returning cached vehicle data due to error: #{e.message}")
      @user.tesla_vehicle_cached_data
    else
      raise
    end
  end

  # POST wake up vehicle
  def wake_up(vehicle_id)
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    conn = Faraday.new(url: FLEET_API_URL) do |f|
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

  def with_caching(key, ttl, &block)
    cache_key = "tesla_fleet:#{@user.id}:#{key}"

    Rails.cache.fetch(cache_key, expires_in: ttl) do
      block.call
    end
  end

  def fleet_api_url
    FLEET_API_URL
  end
end
