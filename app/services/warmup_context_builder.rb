class WarmupContextBuilder
  COLD_THRESHOLD_C = 10
  LOOKBACK = 7.days

  def initialize(vehicle)
    @vehicle = vehicle
    @since = LOOKBACK.ago
  end

  def build
    sections = [
      vehicle_section,
      trips_section,
      telemetry_logs_section
    ].compact

    sections.join("\n\n")
  end

  def cold_enough?
    observed_temperatures_c.any? { |temp| temp <= COLD_THRESHOLD_C }
  end

  private

  def vehicle_section
    data = @vehicle.cached_data.presence || {}
    climate = data["climate_state"] || {}

    lines = [
      "Vehicle: #{@vehicle.display_name || @vehicle.vin}",
      "VIN: #{@vehicle.vin}",
      "Cached climate: outside_temp=#{climate['outside_temp']}, inside_temp=#{climate['inside_temp']}, is_climate_on=#{climate['is_climate_on']}"
    ]

    lines.join("\n")
  end

  def trips_section
    trips = @vehicle.trips.where("started_at >= ?", @since).includes(:intervals).order(:started_at)
    return nil if trips.empty?

    header = "Trips (past #{LOOKBACK.in_days.to_i} days):"
    body = trips.map do |trip|
      [
        "Trip ##{trip.id}: #{trip.started_at.iso8601} -> #{trip.ended_at&.iso8601 || 'ongoing'}",
        "  status=#{trip.trip_status}, distance_km=#{trip.distance_km}, avg_speed_kmh=#{trip.avg_speed_kmh}",
        "  start_battery=#{trip.start_battery_percent}%, end_battery=#{trip.end_battery_percent}%",
        interval_summary(trip)
      ].join("\n")
    end

    [header, *body].join("\n")
  end

  def interval_summary(trip)
    return "  intervals: none" if trip.intervals.empty?

    first = trip.intervals.chronological.first
    last = trip.intervals.reverse_chronological.first

    "  intervals: count=#{trip.intervals.size}, first=#{first.recorded_at.iso8601}, last=#{last.recorded_at.iso8601}, first_speed_kmh=#{first.speed_kmh}, last_speed_kmh=#{last.speed_kmh}"
  end

  def telemetry_logs_section
    return nil unless defined?(TelemetryLog)

    logs = TelemetryLog.where(vin: @vehicle.vin, created_at: @since..).order(:created_at)
    return nil if logs.empty?

    header = "Telemetry logs (past #{LOOKBACK.in_days.to_i} days):"
    body = logs.map do |log|
      data = log.data.is_a?(Hash) ? log.data : {}
      temps = extract_temperatures_from_payload(data)
      temp_text = temps.any? ? temps.map { |t| format("%.1fC", t) }.join(", ") : "none"

      "log #{log.created_at.iso8601}: gear=#{data['Gear'] || data[:Gear]}, soc=#{data['Soc'] || data[:Soc]}, temps=#{temp_text}, location=#{format_location(data)}"
    end

    [header, *body].join("\n")
  end

  def format_location(data)
    location = data["Location"] || data[:Location] || {}
    lat = location["latitude"] || location[:latitude]
    lon = location["longitude"] || location[:longitude]
    return "unknown" if lat.blank? || lon.blank?

    "(#{lat}, #{lon})"
  end

  def observed_temperatures_c
    temps = []

    climate = @vehicle.cached_data&.dig("climate_state") || {}
    temps << climate["outside_temp"].to_f if climate["outside_temp"].present?
    temps << climate["inside_temp"].to_f if climate["inside_temp"].present?

    if defined?(TelemetryLog)
      TelemetryLog.where(vin: @vehicle.vin, created_at: @since..).find_each do |log|
        data = log.data.is_a?(Hash) ? log.data : {}
        temps.concat(extract_temperatures_from_payload(data))
      end
    end

    temps.compact
  end

  def extract_temperatures_from_payload(data)
    keys = %w[OutsideTemp InsideTemp outside_temp inside_temp]
    keys.filter_map do |key|
      value = data[key] || data[key.to_sym]
      next if value.blank? || value == "<invalid>"

      value.to_f
    end
  end
end
