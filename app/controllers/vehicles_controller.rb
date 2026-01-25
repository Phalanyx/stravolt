class VehiclesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:show, :refresh, :start_telemetry, :stop_telemetry]

  def index
    # Auto-sync vehicles if user has none
    initialize_vehicles if current_user.vehicles.empty?

    @vehicles = current_user.vehicles.ordered_by_name
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
