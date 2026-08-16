class ScheduleWarmupJob < ApplicationJob
  queue_as :default

  def perform
    Vehicle.includes(:user).find_each do |vehicle|
      schedule_for_vehicle(vehicle)
    rescue StandardError => e
      Rails.logger.error("ScheduleWarmupJob failed for vehicle #{vehicle.id}: #{e.message}")
    end
  end

  private

  def schedule_for_vehicle(vehicle)
    user = vehicle.user
    return unless user.tesla_verified?

    context_builder = WarmupContextBuilder.new(vehicle)
    unless context_builder.cold_enough?
      Rails.logger.info("Skipping warmup scheduling for vehicle #{vehicle.id}: no temperatures at or below #{WarmupContextBuilder::COLD_THRESHOLD_C}C in the past week")
      return
    end

    context_text = context_builder.build
    warmup_at = AiService.new.recommend_warmup_time(context_text)
    if warmup_at.blank?
      Rails.logger.info("AI did not recommend a warmup time for vehicle #{vehicle.id}")
      return
    end

    if warmup_at <= Time.current
      Rails.logger.info("Skipping past warmup time #{warmup_at.iso8601} for vehicle #{vehicle.id}")
      return
    end

    ExecuteWarmupJob.set(wait_until: warmup_at).perform_later(vehicle.id)
    Rails.logger.info("Scheduled ExecuteWarmupJob for vehicle #{vehicle.id} at #{warmup_at.iso8601}")
  end
end
