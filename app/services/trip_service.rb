class TripService
  DRIVING_GEARS = %w[D R N].freeze

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
      handle_parked
    elsif driving?
      handle_driving
    else
      { success: true, message: "Skipped: unrecognized gear state" }
    end
  end

  private

  def parked?
    @gear.to_s.upcase == 'P' || @gear.to_s == '<invalid>'
  end

  def driving?
    DRIVING_GEARS.include?(@gear.to_s.upcase)
  end

  def handle_parked
    if @vehicle.has_active_trip?
      record_gear
      return complete_trip
    end

    # Only create a parked snapshot when transitioning into park. A car streams
    # telemetry continuously while parked, so consecutive parked frames must not
    # mint a new empty trip each time.
    unless parked_transition?
      record_gear
      return { success: true, message: "Skipped: already parked" }
    end

    record_gear
    create_empty_trip
  end

  def handle_driving
    record_gear
    @vehicle.has_active_trip? ? add_interval : start_trip
  end

  def parked_transition?
    @vehicle.last_gear.nil? || DRIVING_GEARS.include?(@vehicle.last_gear.to_s.upcase)
  end

  def record_gear
    normalized = @gear.to_s
    return if @vehicle.last_gear == normalized

    @vehicle.update!(last_gear: normalized)
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
