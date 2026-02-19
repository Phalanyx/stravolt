class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    return unless current_user.tesla_verified?

    # Initialize vehicles on first load
    initialize_vehicles unless current_user.has_vehicle_configured?

    # Get first vehicle (primary vehicle)
    @vehicle = current_user.vehicles.first
    return unless @vehicle

    # Only fetch new stats if explicitly requested via refresh parameter
    if params[:refresh] == 'true'
      fetch_vehicle_stats
    else
      # Load cached data from database
      @vehicle_data = @vehicle.cached_data
    end

  rescue TeslaFleetErrors::VehicleAsleepError => e
    # Attempt to wake the vehicle
    service = FleetClient.new(current_user)
    if service.wake_up(@vehicle.tesla_vehicle_id)
      @error = "Vehicle is waking up. Please refresh in a few moments."
    else
      @error = "Your vehicle is asleep and could not be woken up. Try again from the Tesla app."
    end
    # Show cached data even if vehicle is asleep
    @vehicle_data = @vehicle.cached_data
  rescue TeslaFleetErrors::ApiUnavailableError
    @error = "Tesla API is temporarily unavailable. Showing cached data."
    @vehicle_data = @vehicle.cached_data
  rescue => e
    Rails.logger.error("Dashboard error: #{e.message}")
    @error = "Unable to fetch vehicle data."
    @vehicle_data = @vehicle&.cached_data
  end

  private

  def initialize_vehicles
    service = FleetClient.new(current_user)
    vehicles = service.fetch_vehicles

    vehicles.each do |vehicle_data|
      current_user.vehicles.find_or_create_by!(tesla_vehicle_id: vehicle_data['id'].to_s) do |v|
        v.vin = vehicle_data['vin']
        v.display_name = vehicle_data['display_name']
        v.cached_data = {}
      end
    end

    @vehicle = current_user.vehicles.first
  rescue => e
    Rails.logger.error("Error initializing vehicles: #{e.message}")
  end

  def fetch_vehicle_stats
    service = FleetClient.new(current_user)
    data = service.fetch_vehicle_data(@vehicle.tesla_vehicle_id)

    # Store in database (updated_at will be set automatically)
    @vehicle.update!(cached_data: data)

    @vehicle_data = data
  end
end
