class User < ApplicationRecord
  include TeslaAuthenticable

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Encrypt Tesla tokens using Rails 8 built-in encryption
  encrypts :access_token, :refresh_token

  # Tesla connection status
  enum :tesla_status, {
    pending: 0,    # No Tesla connection
    started: 1,    # OAuth handshake complete, but not verified with Fleet API
    verified: 2    # Fleet API token obtained with correct audience
  }, prefix: :tesla

  # Check if user has connected Tesla account
  def tesla_connected?
    access_token.present? && !tesla_pending?
  end

  # Check if access token is still valid
  def valid_access_token?
    return false unless access_token.present? && token_expires_at.present?
    token_expires_at > 1.minute.from_now
  end
end
