RSpec.shared_context "with telemetry auth" do
  let(:telemetry_password) { "supersecret" }

  around do |example|
    original = ENV["TELEMETRY_PASSWORD"]
    ENV["TELEMETRY_PASSWORD"] = telemetry_password
    example.run
  ensure
    ENV["TELEMETRY_PASSWORD"] = original
  end

  # Returns an Authorization header hash. Pass a custom token to test rejection.
  def bearer_token(password = telemetry_password)
    { "Authorization" => "Bearer #{password}" }
  end
end
