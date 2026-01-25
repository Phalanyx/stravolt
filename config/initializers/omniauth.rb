require 'omniauth/strategies/tesla'

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :tesla,
           ENV['TESLA_CLIENT_ID'],
           ENV['TESLA_CLIENT_SECRET'],
           {
             scope: 'openid offline_access vehicle_device_data vehicle_location vehicle_cmds vehicle_charging_cmds',
             callback_path: '/auth/tesla/callback'
           }
end

# Configure OmniAuth for Rails CSRF protection
OmniAuth.config.allowed_request_methods = [:post, :get]
OmniAuth.config.silence_get_warning = true
