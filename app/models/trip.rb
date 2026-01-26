class Trip < ApplicationRecord
  belongs_to :vehicle
  has_many :intervals, dependent: :destroy

  validates :started_at, presence: true
  validates :trip_status, presence: true, inclusion: { in: %w[in_progress completed] }
  validates :vehicle, presence: true

  scope :in_progress, -> { where(trip_status: 'in_progress') }
  scope :completed, -> { where(trip_status: 'completed') }
  scope :for_vehicle, ->(vehicle_id) { where(vehicle_id: vehicle_id) }
  scope :recent, -> { order(started_at: :desc) }

  # Complete the trip and calculate final metrics
  def complete!(final_location:, final_battery:, final_timestamp:)
    self.ended_at = final_timestamp
    self.end_latitude = final_location[:latitude]
    self.end_longitude = final_location[:longitude]
    self.end_battery_percent = final_battery

    if start_battery_percent.present? && final_battery.present?
      self.battery_consumed_percent = start_battery_percent - final_battery
    end

    self.trip_status = 'completed'

    recalculate_metrics!

    save!

    # Clear the active trip reference from the vehicle
    vehicle.update!(active_trip: nil)
  end

  # Recalculate trip metrics from intervals
  def recalculate_metrics!
    return unless intervals.any?

    speeds = intervals.pluck(:speed_kmh).compact
    self.max_speed_kmh = speeds.max if speeds.any?
    self.avg_speed_kmh = speeds.sum / speeds.size if speeds.any?

    self.distance_km = intervals.sum(:distance_from_previous_km)
  end

  # Get trip duration in seconds
  def duration_seconds
    return nil unless started_at
    end_time = ended_at || Time.current
    (end_time - started_at).to_i
  end

  # Get formatted trip duration
  def duration_formatted
    return 'Ongoing' unless ended_at
    seconds = duration_seconds
    return nil unless seconds

    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    if hours > 0
      "#{hours}h #{minutes}m #{secs}s"
    elsif minutes > 0
      "#{minutes}m #{secs}s"
    else
      "#{secs}s"
    end
  end
end
