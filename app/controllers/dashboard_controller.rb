class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    return unless current_user.tesla_verified?

    # Initialize vehicle on first load
    initialize_vehicle unless current_user.has_vehicle_configured?

    # Fetch stats if vehicle configured
    fetch_vehicle_stats if current_user.has_vehicle_configured?

  rescue TeslaFleetErrors::VehicleAsleepError => e
    # Attempt to wake the vehicle
    service = TeslaFleetService.new(current_user)
    if service.wake_up(current_user.tesla_vehicle_id)
      @error = "Vehicle is waking up. Please refresh in a few moments."
    else
      @error = "Your vehicle is asleep and could not be woken up. Try again from the Tesla app."
    end
  rescue TeslaFleetErrors::ApiUnavailableError
    @error = "Tesla API is temporarily unavailable. Showing cached data."
  rescue => e
    Rails.logger.error("Dashboard error: #{e.message}")
    @error = "Unable to fetch vehicle data."
  end

  private

  def initialize_vehicle
    service = TeslaFleetService.new(current_user)
    vehicles = service.fetch_vehicles
    if vehicles.any?
      current_user.update!(
        tesla_vehicle_id: vehicles.first['id'],
        tesla_vehicle_vin: vehicles.first['vin'],
        tesla_vehicle_name: vehicles.first['display_name']
      )
    end
  end

  def fetch_vehicle_stats
    service = TeslaFleetService.new(current_user)
    @vehicle_data = service.fetch_vehicle_data(current_user.tesla_vehicle_id)
  end
end
