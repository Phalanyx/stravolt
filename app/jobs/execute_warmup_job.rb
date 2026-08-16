class ExecuteWarmupJob < ApplicationJob
  queue_as :default

  def perform(vehicle_id)
    vehicle = Vehicle.find_by(id: vehicle_id)
    return unless vehicle

    user = vehicle.user
    return unless user.tesla_verified?

    client = TelemetryProxyClient.new(user)
    client.wake_up(vehicle.tesla_vehicle_id) unless vehicle_online?(vehicle)

    if client.start_preconditioning(vehicle)
      Rails.logger.info("Started vehicle preconditioning for vehicle #{vehicle.id}")
    else
      Rails.logger.warn("Failed to start vehicle preconditioning for vehicle #{vehicle.id}")
    end
  rescue StandardError => e
    Rails.logger.error("ExecuteWarmupJob failed for vehicle #{vehicle_id}: #{e.message}")
    raise
  end

  private

  def vehicle_online?(vehicle)
    state = vehicle.cached_data.dig("vehicle_state", "state")
    state.present? && state != "asleep"
  end
end
