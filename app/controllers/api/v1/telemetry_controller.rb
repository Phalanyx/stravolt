module Api
  module V1
    class TelemetryController < Api::BaseController
      # Skip authentication for health check
      skip_before_action :authenticate_telemetry_server!, only: [:health]

      # POST /api/v1/telemetry/ingest
      def ingest
        service = TelemetryIngestService.new(telemetry_params)
        result = service.process

        if result[:success]
          render json: {
            status: 'success',
            trip_id: result[:trip]&.id,
            trip_status: result[:trip]&.trip_status,
            message: result[:message]
          }.compact, status: :created
        else
          render json: {
            status: 'error',
            errors: result[:errors]
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/telemetry/health
      def health
        render json: {
          status: 'healthy',
          timestamp: Time.current.iso8601
        }, status: :ok
      end

      private

      def telemetry_params
        params.permit(:vin, :timestamp, data: [:Gear, :Soc, :VehicleSpeed, Location: [:latitude, :longitude]])
      end
    end
  end
end
