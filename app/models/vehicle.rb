class Vehicle < ApplicationRecord
  belongs_to :user

  validates :tesla_vehicle_id, presence: true, uniqueness: { scope: :user_id }
  validates :vin, presence: true, format: { with: /\A[A-HJ-NPR-Z0-9]{17}\z/ }
  validates :user, presence: true

  scope :with_telemetry_active, -> { where(telemetry_active: true) }
  scope :ordered_by_name, -> { order(:display_name) }

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
end
