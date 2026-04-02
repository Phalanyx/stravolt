class TelemetryLog < ApplicationRecord
  validates :vin, presence: true
end
