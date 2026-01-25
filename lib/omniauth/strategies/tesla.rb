require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    class Tesla < OmniAuth::Strategies::OAuth2
      option :name, 'tesla'

      # CRITICAL: Both authorize and token URLs must use the same regional endpoint
      option :client_options, {
        site: 'https://fleet-auth.prd.vn.cloud.tesla.com',
        authorize_url: '/oauth2/v3/authorize',  # Relative path from site
        token_url: '/oauth2/v3/token',           # Relative path from site
        auth_scheme: :request_body               # Send credentials in body, not Basic Auth header
      }

      # Force token method to POST with credentials in body
      option :token_options, {
        mode: :body,
        param_name: 'client_id'
      }

      # Updated scopes to include vehicle commands and charging commands
      option :scope, 'openid offline_access vehicle_device_data vehicle_location vehicle_cmds vehicle_charging_cmds'

      # Ensure response_type is set correctly for authorization
      def authorize_params
        super.tap do |params|
          params[:response_type] = 'code'
          params[:scope] = options[:scope]
        end
      end

      # Ensure redirect_uri and credentials are included in token exchange
      def token_params
        super.tap do |params|
          params[:client_id] = options.client_id
          params[:client_secret] = options.client_secret
          params[:redirect_uri] = callback_url
        end
      end

      # Parse user info from token response
      uid { raw_info['sub'] }

      info do
        {
          email: raw_info['email'],
          name: raw_info['name']
        }
      end

      extra do
        {
          'raw_info' => raw_info
        }
      end

      def raw_info
        @raw_info ||= access_token.params
      end

      def callback_url
        full_host + script_name + callback_path
      end
    end
  end
end
