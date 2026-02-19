class TripService
  def initialize(vehicle, gear:, location:, battery:, speed:, timestamp:)
    @vehicle   = vehicle
    @gear      = gear
    @location  = location   # { latitude:, longitude: }
    @battery   = battery
    @speed     = speed
    @timestamp = timestamp  # already a parsed Time object
  end

  def process
    if parked?
      @vehicle.has_active_trip? ? complete_trip : create_empty_trip
    elsif driving?
      @vehicle.has_active_trip? ? add_interval : start_trip
    else
      { success: true, message: "Skipped: unrecognized gear state" }
    end
  end

  private

  def parked?
    @gear.to_s.upcase == 'P' || @gear.to_s == '<invalid>'
  end

  def driving?
    %w[D R N].include?(@gear.to_s.upcase)
  end

  def complete_trip
    trip = @vehicle.active_trip
    trip.complete!(
      final_location:  @location,
      final_battery:   @battery,
      final_timestamp: @timestamp
    )
    { success: true, trip: trip }
  end

  def create_empty_trip
    trip = @vehicle.trips.create!(
      started_at:            @timestamp,
      ended_at:              @timestamp,
      start_latitude:        @location[:latitude],
      start_longitude:       @location[:longitude],
      start_battery_percent: @battery,
      end_latitude:          @location[:latitude],
      end_longitude:         @location[:longitude],
      end_battery_percent:   @battery,
      trip_status:           'completed'
    )
    { success: true, trip: trip, message: "Parked location recorded" }
  end

  def start_trip
    trip = @vehicle.trips.create!(
      started_at:            @timestamp,
      start_latitude:        @location[:latitude],
      start_longitude:       @location[:longitude],
      start_battery_percent: @battery,
      trip_status:           'in_progress'
    )
    @vehicle.update!(active_trip: trip)
    { success: true, trip: trip }
  end

  def add_interval
    trip = @vehicle.active_trip
    interval = trip.intervals.find_or_create_by!(recorded_at: @timestamp) do |int|
      int.latitude        = @location[:latitude]
      int.longitude       = @location[:longitude]
      int.speed_kmh       = @speed
      int.battery_percent = @battery
      int.gear            = @gear
    end
    { success: true, trip: trip, interval: interval }
  end
end
