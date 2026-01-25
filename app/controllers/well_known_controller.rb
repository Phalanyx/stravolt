class WellKnownController < ApplicationController
  skip_before_action :verify_authenticity_token

  def public_key
    public_key_path = Rails.root.join('public-key.pem')

    if File.exist?(public_key_path)
      send_file public_key_path,
                type: 'application/x-pem-file',
                disposition: 'inline'
    else
      render plain: "Public key not found. Please generate EC key pair first.", status: :not_found
    end
  end
end
