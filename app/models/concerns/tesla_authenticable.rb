module TeslaAuthenticable
  extend ActiveSupport::Concern

  # Refresh Tesla access token if expired or about to expire
  def refresh_tesla_tokens!
    return false unless refresh_token.present?

    conn = Faraday.new(url: 'https://fleet-auth.prd.vn.cloud.tesla.com') do |f|
      f.request :url_encoded
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.post('/oauth2/v3/token') do |req|
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = {
        grant_type: 'refresh_token',
        refresh_token: refresh_token,
        client_id: ENV['TESLA_CLIENT_ID'],
        client_secret: ENV['TESLA_CLIENT_SECRET']
      }
    end

    if response.success?
      data = response.body
      update!(
        access_token: data['access_token'],
        refresh_token: data['refresh_token'],
        token_expires_at: Time.now + data['expires_in'].seconds
      )
      true
    else
      Rails.logger.error("Failed to refresh Tesla token: #{response.body}")
      false
    end
  rescue => e
    Rails.logger.error("Error refreshing Tesla token: #{e.message}")
    false
  end

  # Get a valid access token, refreshing if necessary
  def ensure_valid_tesla_token
    return nil unless tesla_connected?

    if !valid_access_token?
      refresh_tesla_tokens!
    end

    access_token
  end

  # Refresh token with Fleet API audience (required after virtual key pairing)
  def refresh_with_fleet_api_audience!
    return false unless refresh_token.present?

    conn = Faraday.new(url: 'https://fleet-auth.prd.vn.cloud.tesla.com') do |f|
      f.request :url_encoded
      f.response :json
      f.adapter Faraday.default_adapter
    end

    response = conn.post('/oauth2/v3/token') do |req|
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = {
        grant_type: 'refresh_token',
        refresh_token: refresh_token,
        client_id: ENV['TESLA_CLIENT_ID'],
        client_secret: ENV['TESLA_CLIENT_SECRET'],
        audience: 'https://fleet-api.prd.na.vn.cloud.tesla.com'
      }
    end

    if response.success?
      data = response.body
      update!(
        access_token: data['access_token'],
        refresh_token: data['refresh_token'],
        token_expires_at: Time.now + data['expires_in'].seconds,
        tesla_status: :verified
      )
      true
    else
      Rails.logger.error("Failed to refresh Tesla token with Fleet API audience: #{response.body}")
      false
    end
  rescue => e
    Rails.logger.error("Error refreshing Tesla token with Fleet API audience: #{e.message}")
    false
  end
end
