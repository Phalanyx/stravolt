module Vehicles
  class TelemetryController < ApplicationController
    before_action :authenticate_user!
    before_action :set_vehicle

    # POST /vehicles/:vehicle_id/telemetry
    def create
      client = TelemetryProxyClient.new(current_user)
      config = TelemetryConfigBuilder.build_config(@vehicle)

      response = client.configure(@vehicle, config)

      vehicle_data = FleetClient.new(current_user).fetch_vehicle_data(@vehicle.tesla_vehicle_id) rescue nil

      @vehicle.update!(
        telemetry_active: true,
        telemetry_config: config["config"],
        telemetry_configured_at: Time.current,
        telemetry_synced: response.dig('response', 'synced') || false,
        cached_data: vehicle_data || @vehicle.cached_data
      )

      redirect_to @vehicle, notice: "Telemetry streaming started successfully"
    rescue TeslaFleetErrors::TeslaFleetError => e
      Rails.logger.error("Error starting telemetry for vehicle #{@vehicle.id}: #{e.message}")
      redirect_to @vehicle, alert: "Failed to start telemetry: #{e.message}"
    rescue => e
      Rails.logger.error("Unexpected error starting telemetry: #{e.message}")
      redirect_to @vehicle, alert: "Unable to start telemetry streaming."
    end

    # DELETE /vehicles/:vehicle_id/telemetry
    def destroy
      client = TelemetryProxyClient.new(current_user)

      if client.delete(@vehicle)
        @vehicle.update!(
          telemetry_active: false,
          telemetry_config: nil,
          telemetry_configured_at: nil,
          telemetry_synced: false
        )
        redirect_to @vehicle, notice: "Telemetry streaming stopped successfully"
      else
        redirect_to @vehicle, alert: "Failed to stop telemetry streaming"
      end
    rescue => e
      Rails.logger.error("Error stopping telemetry for vehicle #{@vehicle.id}: #{e.message}")
      redirect_to @vehicle, alert: "Unable to stop telemetry streaming."
    end

    # GET /vehicles/:vehicle_id/telemetry/errors
    def errors
      client = TelemetryProxyClient.new(current_user)
      @errors = client.errors(@vehicle)
    rescue => e
      Rails.logger.error("Error fetching telemetry errors for vehicle #{@vehicle.id}: #{e.message}")
      redirect_to @vehicle, alert: "Unable to fetch telemetry errors."
    end

    private

    def set_vehicle
      @vehicle = current_user.vehicles.find(params[:vehicle_id])
    end
  end
end
