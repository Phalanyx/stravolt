module Api
  class BaseController < ActionController::API
    include TeslaFleetErrors

    before_action :authenticate_telemetry_server!

    rescue_from StandardError, with: :handle_standard_error
    rescue_from ArgumentError, with: :handle_bad_request
    rescue_from VehicleNotFoundError, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_unprocessable_entity

    private

    def authenticate_telemetry_server!
      expected_password = ENV['TELEMETRY_PASSWORD']

      if expected_password.blank?
        Rails.logger.error "TELEMETRY_PASSWORD not configured"
        return render json: { error: 'Server configuration error' }, status: :internal_server_error
      end

      auth_header = request.headers['Authorization']
      unless auth_header
        return render json: { error: 'Missing authorization header' }, status: :unauthorized
      end

      token = auth_header.split(' ').last
      unless token == expected_password
        return render json: { error: 'Invalid authentication token' }, status: :unauthorized
      end
    end

    def handle_standard_error(exception)
      Rails.logger.error "API Error: #{exception.class} - #{exception.message}"
      Rails.logger.error exception.backtrace.join("\n")
      render json: { error: 'Internal server error' }, status: :internal_server_error
    end

    def handle_bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end

    def handle_not_found(exception)
      render json: { error: exception.message }, status: :not_found
    end

    def handle_unprocessable_entity(exception)
      render json: { error: exception.message, details: exception.record&.errors&.full_messages },
             status: :unprocessable_entity
    end
  end
end
