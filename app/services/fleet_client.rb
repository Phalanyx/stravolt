class FleetClient
  include TeslaFleetErrors

  FLEET_API_URL = 'https://fleet-api.prd.na.vn.cloud.tesla.com'

  def initialize(user)
    @user = user
  end

  # GET list of user's vehicles
  def fetch_vehicles
    make_request('/api/1/vehicles')
  end

  # GET comprehensive vehicle data
  def fetch_vehicle_data(vehicle_id)
    endpoints = "charge_state;drive_state;location_data;vehicle_state"
    make_request("/api/1/vehicles/#{vehicle_id}/vehicle_data?endpoints=#{endpoints}")
  end

  private

  def connection
    @connection ||= Faraday.new(url: FLEET_API_URL) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def make_request(endpoint)
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    response = connection.get(endpoint) do |req|
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
