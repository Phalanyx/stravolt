module TeslaApi
  class Client
    BASE_URL = 'https://fleet-api.prd.na.vn.cloud.tesla.com'

    def initialize(user)
      @user = user
    end

    # Get list of vehicles
    def vehicles
      request(:get, '/api/1/vehicles')
    end

    # Get vehicle data
    def vehicle_data(vehicle_id)
      request(:get, "/api/1/vehicles/#{vehicle_id}/vehicle_data")
    end

    # Get vehicle location
    def vehicle_location(vehicle_id)
      request(:get, "/api/1/vehicles/#{vehicle_id}/location_data")
    end

    private

    def request(method, path, body: nil)
      token = @user.ensure_valid_tesla_token
      return { error: 'No valid Tesla token' } unless token

      conn = Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end

      response = conn.send(method, path) do |req|
        req.headers['Authorization'] = "Bearer #{token}"
        req.headers['Content-Type'] = 'application/json'
        req.body = body if body
      end

      if response.success?
        response.body
      else
        Rails.logger.error("Tesla API error: #{response.status} - #{response.body}")
        { error: response.body }
      end
    rescue => e
      Rails.logger.error("Tesla API request failed: #{e.message}")
      { error: e.message }
    end
  end
end
