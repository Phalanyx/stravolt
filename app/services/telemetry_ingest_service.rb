class TelemetryIngestService
  attr_reader :vin, :timestamp, :data, :metadata, :vehicle, :errors

  def initialize(params)
    @vin = params[:vin]
    @metadata = params[:metadata] || {}
    @data = params[:data] || {}
    @timestamp = extract_timestamp(params)
    @errors = []
  end

  # Main entry point
  def process
    validate_data!
    find_vehicle!

    gear = data[:Gear] || data['Gear']

    result = if gear.to_s.upcase == 'P'
      handle_park_state
    elsif %w[D R N].include?(gear.to_s.upcase)
      handle_driving_state(gear)
    else
      { success: false, errors: ["Invalid gear state: #{gear}"] }
    end

    result
  rescue StandardError => e
    { success: false, errors: [e.message] }
  end

  private

  # Validate required telemetry data
  def validate_data!
    raise ArgumentError, "VIN is required" if vin.blank?
    raise ArgumentError, "Timestamp is required" if timestamp.blank?
    raise ArgumentError, "Data payload is required" if data.blank?
    raise ArgumentError, "Gear is required" unless data[:Gear] || data['Gear']

    # Parse timestamp
    @parsed_timestamp = Time.zone.parse(timestamp.to_s)
    raise ArgumentError, "Invalid timestamp format" unless @parsed_timestamp
  end

  # Find vehicle by VIN
  def find_vehicle!
    @vehicle = Vehicle.find_by(vin: vin)
    raise VehicleNotFoundError, "Vehicle with VIN #{vin} not found" unless @vehicle
    raise ArgumentError, "Telemetry not active for this vehicle" unless @vehicle.telemetry_active

    @vehicle
  end

  # Handle driving states (D, R, N)
  def handle_driving_state(gear)
    trip = @vehicle.active_trip || create_new_trip

    interval = add_interval_to_trip(trip, gear)

    {
      success: true,
      trip: trip,
      interval: interval
    }
  end

  # Handle park state
  def handle_park_state
    if @vehicle.has_active_trip?
      trip = complete_active_trip
      {
        success: true,
        trip: trip,
        interval: nil
      }
    else
      {
        success: true,
        trip: nil,
        interval: nil,
        message: "No active trip to complete"
      }
    end
  end

  # Create a new trip
  def create_new_trip
    location = extract_location
    battery = extract_battery

    trip = @vehicle.trips.create!(
      started_at: @parsed_timestamp,
      start_latitude: location[:latitude],
      start_longitude: location[:longitude],
      start_battery_percent: battery,
      trip_status: 'in_progress'
    )

    @vehicle.update!(active_trip: trip)

    trip
  end

  # Add interval to existing trip (with idempotency)
  def add_interval_to_trip(trip, gear)
    location = extract_location
    battery = extract_battery
    speed = extract_speed

    # Use find_or_create_by to ensure idempotency
    interval = trip.intervals.find_or_create_by!(recorded_at: @parsed_timestamp) do |int|
      int.latitude = location[:latitude]
      int.longitude = location[:longitude]
      int.speed_kmh = speed
      int.battery_percent = battery
      int.gear = gear
    end

    interval
  end

  # Complete the active trip
  def complete_active_trip
    trip = @vehicle.active_trip
    return nil unless trip

    location = extract_location
    battery = extract_battery

    trip.complete!(
      final_location: location,
      final_battery: battery,
      final_timestamp: @parsed_timestamp
    )

    trip
  end

  # Extract location from data
  def extract_location
    location_data = data[:Location] || data['Location'] || {}

    {
      latitude: location_data[:latitude] || location_data['latitude'],
      longitude: location_data[:longitude] || location_data['longitude']
    }
  end

  # Extract battery percentage from data
  def extract_battery
    data[:Soc] || data['Soc']
  end

  # Extract speed from data
  def extract_speed
    speed = data[:VehicleSpeed] || data['VehicleSpeed'] || 0
    speed.to_f
  end

  # Extract timestamp from params, metadata, or data
  def extract_timestamp(params)
    # Priority: top-level timestamp > data.CreatedAt > metadata.receivedat
    params[:timestamp] ||
      data[:CreatedAt] || data['CreatedAt'] ||
      convert_receivedat(metadata[:receivedat] || metadata['receivedat'])
  end

  # Convert receivedat (milliseconds since epoch) to ISO8601 string
  def convert_receivedat(receivedat)
    return nil if receivedat.blank?

    Time.at(receivedat.to_i / 1000).utc.iso8601
  end
end
