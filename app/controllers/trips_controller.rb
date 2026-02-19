class TripsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_vehicle

  def index
    @trips = @vehicle.trips.recent
  end

  def show
    @trip      = @vehicle.trips.find(params[:id])
    @intervals = @trip.intervals.chronological
  end

  private

  def find_vehicle
    @vehicle = current_user.vehicles.find(params[:vehicle_id])
  end
end
