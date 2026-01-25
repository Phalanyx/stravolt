class VehicleCommandClient
  include TeslaFleetErrors

  # HTTP proxy running in Docker
  PROXY_URL = 'https://localhost:4443'

  def initialize(user)
    @user = user
  end

  # Lock the vehicle doors
  def lock_doors(vehicle)
    send_command(vehicle, 'door_lock')
  end

  # Unlock the vehicle doors
  def unlock_doors(vehicle)
    send_command(vehicle, 'door_unlock')
  end

  # Flash the vehicle lights
  def flash_lights(vehicle)
    send_command(vehicle, 'flash_lights')
  end

  # Honk the vehicle horn
  def honk_horn(vehicle)
    send_command(vehicle, 'honk_horn')
  end

  # Start climate control
  def start_climate(vehicle)
    send_command(vehicle, 'auto_conditioning_start')
  end

  # Stop climate control
  def stop_climate(vehicle)
    send_command(vehicle, 'auto_conditioning_stop')
  end

  # Set temperature (in Celsius)
  def set_temperature(vehicle, driver_temp:, passenger_temp: nil)
    passenger_temp ||= driver_temp
    send_command(vehicle, 'set_temps', {
      driver_temp: driver_temp,
      passenger_temp: passenger_temp
    })
  end

  # Set charge limit (percentage 50-100)
  def set_charge_limit(vehicle, percent)
    send_command(vehicle, 'set_charge_limit', { percent: percent })
  end

  # Start charging
  def start_charging(vehicle)
    send_command(vehicle, 'charge_start')
  end

  # Stop charging
  def stop_charging(vehicle)
    send_command(vehicle, 'charge_stop')
  end

  # Open charge port
  def open_charge_port(vehicle)
    send_command(vehicle, 'charge_port_door_open')
  end

  # Close charge port
  def close_charge_port(vehicle)
    send_command(vehicle, 'charge_port_door_close')
  end

  # Actuate trunk (rear trunk)
  def actuate_trunk(vehicle)
    send_command(vehicle, 'actuate_trunk', { which_trunk: 'rear' })
  end

  # Actuate frunk (front trunk)
  def actuate_frunk(vehicle)
    send_command(vehicle, 'actuate_trunk', { which_trunk: 'front' })
  end

  # Set sentry mode
  def set_sentry_mode(vehicle, enabled)
    send_command(vehicle, 'set_sentry_mode', { on: enabled })
  end

  # Remote start
  def remote_start(vehicle)
    send_command(vehicle, 'remote_start_drive')
  end

  private

  def send_command(vehicle, command, params = {})
    token = @user.ensure_valid_tesla_token
    raise TokenExpiredError, "Unable to refresh Tesla token" unless token.present?

    # Create SSL context that accepts self-signed certificates (for local development)
    ssl_options = {
      verify: false # In production, you should verify with proper CA cert
    }

    conn = Faraday.new(url: PROXY_URL, ssl: ssl_options) do |f|
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.post("/api/1/vehicles/#{vehicle.vin}/command/#{command}") do |req|
      req.headers['Authorization'] = "Bearer #{token}"
      req.headers['Content-Type'] = 'application/json'
      req.body = params.to_json
    end

    handle_response(response)
  rescue Faraday::Error => e
    Rails.logger.error("Vehicle command error: #{e.message}")
    raise ApiUnavailableError, "Vehicle command proxy is unavailable"
  end

  def handle_response(response)
    case response.status
    when 200
      response.body
    when 401
      raise TokenExpiredError, "Tesla token expired"
    when 404
      raise VehicleNotFoundError, "Vehicle not found"
    when 408
      raise VehicleAsleepError, "Vehicle is asleep"
    when 500..599
      raise ApiUnavailableError, "Vehicle command proxy server error"
    else
      raise TeslaFleetError, "Unexpected response: #{response.status}"
    end
  end
end
