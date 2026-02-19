class VehiclesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_vehicle, only: [:show, :refresh]

  def index
    # Auto-sync vehicles if user has none
    initialize_vehicles if current_user.vehicles.empty?

    @vehicles = current_user.vehicles.ordered_by_name
  end

  def show
    @vehicle_data  = @vehicle.cached_data
    @recent_trips  = @vehicle.trips.recent.limit(5)
  end

  def refresh
    fleet_client = FleetClient.new(current_user)
    data = fleet_client.fetch_vehicle_data(@vehicle.tesla_vehicle_id)
    Rails.logger.info("Refreshed vehicle data: #{data}")
    # Update cached data
    @vehicle.update!(cached_data: data)

    redirect_to @vehicle, notice: "Vehicle data refreshed successfully"
  rescue TeslaFleetErrors::VehicleAsleepError
    # Attempt to wake the vehicle
    proxy_client = TelemetryProxyClient.new(current_user)
    if proxy_client.wake_up(@vehicle.tesla_vehicle_id)
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

  private

  def set_vehicle
    @vehicle = current_user.vehicles.find(params[:id])
  end

  def initialize_vehicles
    return unless current_user.tesla_verified?

    fleet_client = FleetClient.new(current_user)
    vehicles = fleet_client.fetch_vehicles

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
