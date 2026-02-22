class Vehicle < ApplicationRecord
  belongs_to :user
  has_many :trips, dependent: :destroy
  belongs_to :active_trip, class_name: 'Trip', optional: true

  serialize :cached_data, coder: JSON
  serialize :telemetry_config, coder: JSON

  validates :tesla_vehicle_id, presence: true, uniqueness: { scope: :user_id }
  validates :vin, presence: true, format: { with: /\A[A-HJ-NPR-Z0-9]{17}\z/ }
  validates :user, presence: true

  scope :with_telemetry_active, -> { where(telemetry_active: true) }
  scope :ordered_by_name, -> { order(:display_name) }
  scope :with_active_trip, -> { where.not(active_trip_id: nil) }

  def cached_data_stale?
    updated_at < 5.minutes.ago
  end

  def battery_level
    cached_data.dig('charge_state', 'battery_level')
  end

  def telemetry_status
    return "Inactive" unless telemetry_active
    telemetry_synced ? "Active (Synced)" : "Active (Pending Sync)"
  end

  def has_active_trip?
    active_trip_id.present?
  end
end
