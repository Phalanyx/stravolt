class Tesla::PartnerController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:register]

  # POST /tesla/partner/register
  def register
    # Get the domain from the request or environment variable
    domain = params[:domain] || request.host

    # Get a partner authentication token using client credentials
    partner_token = get_partner_token

    unless partner_token
      return redirect_to dashboard_path, alert: 'Failed to get partner authentication token. Check your Tesla credentials.'
    end

    # Call Tesla's partner registration endpoint
    conn = Faraday.new(url: 'https://fleet-api.prd.na.vn.cloud.tesla.com') do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.post('/api/1/partner_accounts') do |req|
      req.headers['Authorization'] = "Bearer #{partner_token}"
      req.headers['Content-Type'] = 'application/json'
      req.body = { domain: domain }
    end

    if response.success?
      redirect_to dashboard_path, notice: "Partner account registered successfully for domain: #{domain}"
    else
      error_msg = response.body.is_a?(Hash) ? response.body['error'] || response.body.inspect : response.body
      Rails.logger.error("Partner registration failed: #{response.status} - #{error_msg}")
      redirect_to dashboard_path, alert: "Partner registration failed: #{error_msg}"
    end
  rescue => e
    Rails.logger.error("Partner registration error: #{e.message}")
    redirect_to dashboard_path, alert: "Partner registration error: #{e.message}"
  end

  # GET /tesla/partner/status
  # Check if partner account is registered
  def status
    render json: {
      domain: request.host,
      public_key_url: "#{request.protocol}#{request.host_with_port}/.well-known/appspecific/com.tesla.3p.public-key.pem",
      client_id_configured: ENV['TESLA_CLIENT_ID'].present?,
      client_secret_configured: ENV['TESLA_CLIENT_SECRET'].present?
    }
  end

  private

  # Get a partner authentication token using client credentials
  def get_partner_token
    conn = Faraday.new(url: 'https://fleet-auth.prd.vn.cloud.tesla.com') do |f|
      f.request :url_encoded
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.post('/oauth2/v3/token') do |req|
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = {
        grant_type: 'client_credentials',
        client_id: ENV['TESLA_CLIENT_ID'],
        client_secret: ENV['TESLA_CLIENT_SECRET'],
        scope: 'openid vehicle_device_data vehicle_cmds vehicle_charging_cmds'
      }
    end

    if response.success?
      response.body['access_token']
    else
      Rails.logger.error("Failed to get partner token: #{response.body}")
      nil
    end
  rescue => e
    Rails.logger.error("Error getting partner token: #{e.message}")
    nil
  end
end
