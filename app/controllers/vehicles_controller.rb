class VehiclesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:show, :refresh, :start_telemetry, :stop_telemetry,
                                      :lock, :unlock, :flash_lights, :honk_horn,
                                      :start_climate, :stop_climate, :start_charging, :stop_charging]

  def index
    # Auto-sync vehicles if user has none
    initialize_vehicles if current_user.vehicles.empty?

    @vehicles = current_user.vehicles.ordered_by_name
  end

  def telemetry_errors
    service = TeslaFleetService.new(current_user)
    @vehicles = current_user.vehicles.ordered_by_name
    @errors_by_vehicle = {}

    # Fetch errors for each vehicle
    @vehicles.each do |vehicle|
      begin
        @errors_by_vehicle[vehicle.id] = service.fetch_vehicle_telemetry_errors(vehicle)
      rescue => e
        Rails.logger.error("Error fetching telemetry errors for vehicle #{vehicle.id}: #{e.message}")
        @errors_by_vehicle[vehicle.id] = { 'error' => e.message }
      end
    end
  rescue => e
    Rails.logger.error("Unexpected error fetching telemetry errors: #{e.message}")
    redirect_to vehicles_path, alert: "Unable to fetch telemetry errors."
  end

  def show
    @vehicle_data = @vehicle.cached_data
  end

  def refresh
    service = TeslaFleetService.new(current_user)
    data = service.fetch_vehicle_data(@vehicle.tesla_vehicle_id)

    # Update cached data
    @vehicle.update!(cached_data: data)

    redirect_to @vehicle, notice: "Vehicle data refreshed successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    # Attempt to wake the vehicle
    if service.wake_up(@vehicle.tesla_vehicle_id)
      redirect_to @vehicle, alert: "Vehicle is waking up. Please refresh in a few moments."
    else
      redirect_to @vehicle, alert: "Your vehicle is asleep and could not be woken up. Try again from the Tesla app."
    end
  rescue TeslaFleetErrors::ApiUnavailableError
    redirect_to @vehicle, alert: "Tesla API is temporarily unavailable. Please try again later."
  rescue => e
    Rails.logger.error("Error refreshing vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to refresh vehicle data."
  end

  def start_telemetry
    service = TeslaFleetService.new(current_user)
    config = TelemetryConfigBuilder.build_config(@vehicle)

    # Configure telemetry with Tesla API
    response = service.configure_telemetry(@vehicle, config)

    # Update vehicle record - store only the config part, not the vins wrapper
    @vehicle.update!(
      telemetry_active: true,
      telemetry_config: config["config"],
      telemetry_configured_at: Time.current,
      telemetry_synced: response.dig('response', 'synced') || false
    )

    redirect_to @vehicle, notice: "Telemetry streaming started successfully"
  rescue TeslaFleetErrors::TeslaFleetError => e
    Rails.logger.error("Error starting telemetry for vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Failed to start telemetry: #{e.message}"
  rescue => e
    Rails.logger.error("Unexpected error starting telemetry: #{e.message}")
    redirect_to @vehicle, alert: "Unable to start telemetry streaming."
  end

  def stop_telemetry
    service = TeslaFleetService.new(current_user)

    # Delete telemetry configuration
    if service.delete_telemetry_config(@vehicle)
      @vehicle.update!(
        telemetry_active: false,
        telemetry_config: nil,
        telemetry_configured_at: nil,
        telemetry_synced: false
      )
      redirect_to @vehicle, notice: "Telemetry streaming stopped successfully"
    else
      redirect_to @vehicle, alert: "Failed to stop telemetry streaming"
    end
  rescue => e
    Rails.logger.error("Error stopping telemetry for vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to stop telemetry streaming."
  end

  # Vehicle command actions
  def lock
    command_client = VehicleCommandClient.new(current_user)
    command_client.lock_doors(@vehicle)
    redirect_to @vehicle, notice: "Vehicle locked successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error locking vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to lock vehicle."
  end

  def unlock
    command_client = VehicleCommandClient.new(current_user)
    command_client.unlock_doors(@vehicle)
    redirect_to @vehicle, notice: "Vehicle unlocked successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error unlocking vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to unlock vehicle."
  end

  def flash_lights
    command_client = VehicleCommandClient.new(current_user)
    command_client.flash_lights(@vehicle)
    redirect_to @vehicle, notice: "Lights flashed successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error flashing lights on vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to flash lights."
  end

  def honk_horn
    command_client = VehicleCommandClient.new(current_user)
    command_client.honk_horn(@vehicle)
    redirect_to @vehicle, notice: "Horn honked successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error honking horn on vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to honk horn."
  end

  def start_climate
    command_client = VehicleCommandClient.new(current_user)
    command_client.start_climate(@vehicle)
    redirect_to @vehicle, notice: "Climate control started successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error starting climate on vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to start climate control."
  end

  def stop_climate
    command_client = VehicleCommandClient.new(current_user)
    command_client.stop_climate(@vehicle)
    redirect_to @vehicle, notice: "Climate control stopped successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error stopping climate on vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to stop climate control."
  end

  def start_charging
    command_client = VehicleCommandClient.new(current_user)
    command_client.start_charging(@vehicle)
    redirect_to @vehicle, notice: "Charging started successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error starting charging on vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to start charging."
  end

  def stop_charging
    command_client = VehicleCommandClient.new(current_user)
    command_client.stop_charging(@vehicle)
    redirect_to @vehicle, notice: "Charging stopped successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    redirect_to @vehicle, alert: "Vehicle is asleep. Wake it up first."
  rescue => e
    Rails.logger.error("Error stopping charging on vehicle #{@vehicle.id}: #{e.message}")
    redirect_to @vehicle, alert: "Unable to stop charging."
  end

  private

  def set_vehicle
    @vehicle = current_user.vehicles.find(params[:id])
  end

  def initialize_vehicles
    return unless current_user.tesla_verified?

    service = TeslaFleetService.new(current_user)
    vehicles = service.fetch_vehicles

    vehicles.each do |vehicle_data|
      current_user.vehicles.find_or_create_by!(tesla_vehicle_id: vehicle_data['id'].to_s) do |v|
        v.vin = vehicle_data['vin']
        v.display_name = vehicle_data['display_name']
        v.cached_data = {}
      end
    end
  rescue => e
    Rails.logger.error("Error initializing vehicles: #{e.message}")
  end
end
