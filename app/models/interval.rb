class Interval < ApplicationRecord
  belongs_to :trip, counter_cache: true

  validates :recorded_at, presence: true
  validates :recorded_at, uniqueness: { scope: :trip_id }
  validates :latitude, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :speed_kmh, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_create :calculate_distance_from_previous
  after_create :update_trip_metrics

  scope :chronological, -> { order(recorded_at: :asc) }
  scope :reverse_chronological, -> { order(recorded_at: :desc) }
  scope :in_time_range, ->(start_time, end_time) { where(recorded_at: start_time..end_time) }

  private

  # Calculate distance from previous interval using Haversine formula
  def calculate_distance_from_previous
    previous_interval = trip.intervals.chronological.last
    return unless previous_interval

    lat1 = previous_interval.latitude.to_f
    lon1 = previous_interval.longitude.to_f
    lat2 = latitude.to_f
    lon2 = longitude.to_f

    self.distance_from_previous_km = haversine_distance(lat1, lon1, lat2, lon2)
  end

  # Haversine formula to calculate distance between two points on Earth
  def haversine_distance(lat1, lon1, lat2, lon2)
    earth_radius_km = 6371.0

    # Convert degrees to radians
    lat1_rad = lat1 * Math::PI / 180
    lat2_rad = lat2 * Math::PI / 180
    delta_lat = (lat2 - lat1) * Math::PI / 180
    delta_lon = (lon2 - lon1) * Math::PI / 180

    # Haversine formula
    a = Math.sin(delta_lat / 2)**2 +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) *
        Math.sin(delta_lon / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    earth_radius_km * c
  end

  # Update trip metrics after adding interval
  def update_trip_metrics
    trip.recalculate_metrics!
    trip.save!
  end
end
