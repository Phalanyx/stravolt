class TelemetryIngestService
  attr_reader :vin, :timestamp, :data, :metadata, :vehicle, :errors

  def initialize(params)
    @vin = params[:vin]
    @metadata = params[:metadata] || {}
    @data = params[:data] || {}
    @timestamp = extract_timestamp(params)
    @errors = []
  end

  def process
    validate_data!
    find_vehicle!

    gear = data[:Gear] || data['Gear']
    return { success: true, message: "Skipped: no gear data" } if gear.nil?

    TripService.new(
      @vehicle,
      gear:      gear,
      location:  extract_location,
      battery:   extract_battery,
      speed:     extract_speed,
      timestamp: @parsed_timestamp
    ).process
  rescue StandardError => e
    { success: false, errors: [e.message] }
  end

  private

  def validate_data!
    raise ArgumentError, "VIN is required" if vin.blank?
    raise ArgumentError, "Timestamp is required" if timestamp.blank?
    raise ArgumentError, "Data payload is required" if data.blank?

    @parsed_timestamp = Time.zone.parse(timestamp.to_s)
    raise ArgumentError, "Invalid timestamp format" unless @parsed_timestamp
  end

  def find_vehicle!
    @vehicle = Vehicle.find_by(vin: vin)
    raise VehicleNotFoundError, "Vehicle with VIN #{vin} not found" unless @vehicle
    raise ArgumentError, "Telemetry not active for this vehicle" unless @vehicle.telemetry_active

    @vehicle
  end

  def extract_location
    location_data = data[:Location] || data['Location'] || {}

    {
      latitude: location_data[:latitude] || location_data['latitude'],
      longitude: location_data[:longitude] || location_data['longitude']
    }
  end

  def extract_battery
    data[:Soc] || data['Soc']
  end

  def extract_speed
    speed = data[:VehicleSpeed] || data['VehicleSpeed'] || 0
    speed.to_f
  end

  def extract_timestamp(params)
    params[:timestamp] ||
      data[:CreatedAt] || data['CreatedAt'] ||
      convert_receivedat(metadata[:receivedat] || metadata['receivedat'])
  end

  def convert_receivedat(receivedat)
    return nil if receivedat.blank?

    Time.at(receivedat.to_i / 1000).utc.iso8601
  end
end
