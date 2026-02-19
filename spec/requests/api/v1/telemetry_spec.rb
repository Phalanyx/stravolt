require "rails_helper"

RSpec.describe "Api::V1::Telemetry", type: :request do
  include_context "with telemetry auth"

  let(:vin) { "LRW3E1FA4PC921681" }

  # Mirrors the real payload shape dispatched by fleet-telemetry
  let(:telemetry_payload) do
    {
      telemetry: {
        vin: vin,
        metadata: {
          device_client_version: "1.1.0",
          receivedat: "1771473441000",
          txid: "b1a0f5c072284d00b936f1-000000001",
          txtype: "V",
          version: "0",
          vin: vin
        },
        data: {
          CreatedAt: "2026-02-19T03:57:14Z",
          Gear: "<invalid>",
          IsResend: false,
          Location: { latitude: 43.906558, longitude: -78.712022 },
          Soc: 98.89,
          VehicleSpeed: "<invalid>",
          Vin: vin
        }
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Health check (no auth required)
  # ---------------------------------------------------------------------------
  describe "GET /api/v1/telemetry/health" do
    it "returns 200 with a healthy status" do
      get "/api/v1/telemetry/health"

      expect(response).to have_http_status(:ok)
      expect(json_response["status"]).to eq("healthy")
      expect(json_response["timestamp"]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Ingest
  # ---------------------------------------------------------------------------
  describe "POST /api/v1/telemetry/ingest" do
    let(:service_double) { instance_double(TelemetryIngestService) }

    before do
      allow(TelemetryIngestService).to receive(:new).and_return(service_double)
    end

    context "when the Authorization header is missing" do
      it "returns 401" do
        post "/api/v1/telemetry/ingest", params: telemetry_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("Missing authorization header")
      end
    end

    context "when the Authorization token is wrong" do
      it "returns 401" do
        post "/api/v1/telemetry/ingest",
             params: telemetry_payload,
             headers: bearer_token("wrongtoken"),
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("Invalid authentication token")
      end
    end

    context "when TELEMETRY_PASSWORD is not configured" do
      around do |example|
        original = ENV.delete("TELEMETRY_PASSWORD")
        example.run
      ensure
        ENV["TELEMETRY_PASSWORD"] = original if original
      end

      it "returns 500" do
        post "/api/v1/telemetry/ingest",
             params: telemetry_payload,
             headers: bearer_token,
             as: :json

        expect(response).to have_http_status(:internal_server_error)
      end
    end

    context "when authenticated" do
      context "and the service processes successfully with a trip" do
        let(:trip) { double("Trip", id: 42, trip_status: "in_progress") }

        before { allow(service_double).to receive(:process).and_return({ success: true, trip: trip }) }

        it "returns 201 with trip_id and trip_status" do
          post "/api/v1/telemetry/ingest",
               params: telemetry_payload,
               headers: bearer_token,
               as: :json

          expect(response).to have_http_status(:created)
          expect(json_response["status"]).to eq("success")
          expect(json_response["trip_id"]).to eq(42)
          expect(json_response["trip_status"]).to eq("in_progress")
        end

        it "initialises the service with the permitted telemetry params" do
          expect(TelemetryIngestService).to receive(:new).with(
            hash_including("vin" => vin)
          ).and_return(service_double)

          post "/api/v1/telemetry/ingest",
               params: telemetry_payload,
               headers: bearer_token,
               as: :json
        end
      end

      context "and the service skips processing (no gear data)" do
        before do
          allow(service_double).to receive(:process).and_return({
            success: true,
            message: "Skipped: no gear data"
          })
        end

        it "returns 201 with the skip message" do
          post "/api/v1/telemetry/ingest",
               params: telemetry_payload,
               headers: bearer_token,
               as: :json

          expect(response).to have_http_status(:created)
          expect(json_response["status"]).to eq("success")
          expect(json_response["message"]).to eq("Skipped: no gear data")
        end
      end

      context "and the service returns a failure" do
        before do
          allow(service_double).to receive(:process).and_return({
            success: false,
            errors: ["Vehicle with VIN #{vin} not found"]
          })
        end

        it "returns 422 with the error list" do
          post "/api/v1/telemetry/ingest",
               params: telemetry_payload,
               headers: bearer_token,
               as: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response["status"]).to eq("error")
          expect(json_response["errors"]).to include("Vehicle with VIN #{vin} not found")
        end
      end
    end
  end
end
