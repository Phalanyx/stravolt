class TelemetryLog < ApplicationRecord
  serialize :metadata, coder: JSON
  serialize :data, coder: JSON

  validates :vin, presence: true
end
