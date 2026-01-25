class TeslaSessionsController < ApplicationController
  before_action :authenticate_user!

  # OAuth callback from Tesla
  def create
    auth = request.env['omniauth.auth']

    # Update current user with Tesla credentials and set status to "started"
    current_user.update!(
      access_token: auth['credentials']['token'],
      refresh_token: auth['credentials']['refresh_token'],
      token_expires_at: Time.at(auth['credentials']['expires_at']),
      tesla_status: :started
    )

    # Try to refresh token with Fleet API audience
    if current_user.refresh_with_fleet_api_audience!
      # Successfully verified with Fleet API
      redirect_to dashboard_path, notice: "Tesla account connected and verified with Fleet API!"
    else
      # Failed to verify - need virtual key pairing first
      redirect_to "https://tesla.com/_ak/#{request.host}", allow_other_host: true
    end
  end

  # Return from virtual key pairing
  def paired
    redirect_to dashboard_path, notice: "Tesla account connected successfully!"
  end

  # Handle OAuth failures
  def failure
    redirect_to dashboard_path, alert: "Failed to connect Tesla account: #{params[:message]}"
  end

  # Disconnect Tesla account
  def destroy
    current_user.update!(
      access_token: nil,
      refresh_token: nil,
      token_expires_at: nil,
      tesla_status: :pending
    )

    redirect_to dashboard_path, notice: "Tesla account disconnected."
  end

  # Refresh token with Fleet API audience
  def refresh_fleet_token
    if current_user.refresh_with_fleet_api_audience!
      redirect_to dashboard_path, notice: "Token refreshed successfully! Your account is now verified with Fleet API."
    else
      redirect_to dashboard_path, alert: "Failed to refresh token with Fleet API audience. Please try again."
    end
  end
end
