require "rails_helper"

# Integration test: exercises the full park → drive × N → park state machine
# end-to-end through the API, touching real DB records.
RSpec.describe "Telemetry drive cycle integration", type: :request do
  include_context "with telemetry auth"

  let(:vehicle) { create(:vehicle, telemetry_active: true) }
  let(:vin)     { vehicle.vin }

  # Base timestamp for the drive cycle — each event is 30 s apart
  let(:base_time) { Time.zone.parse("2026-02-19T08:00:00Z") }

  # Helper: build a full telemetry payload
  def payload(gear:, lat:, lon:, battery:, speed:, offset_seconds: 0)
    t = base_time + offset_seconds.seconds
    {
      telemetry: {
        vin: vin,
        metadata: {
          device_client_version: "1.1.0",
          receivedat: (t.to_i * 1000).to_s,
          txid: "drive-cycle-test-#{offset_seconds}",
          txtype: "V",
          version: "0",
          vin: vin
        },
        data: {
          CreatedAt: t.iso8601,
          Gear: gear,
          IsResend: false,
          Location: { latitude: lat, longitude: lon },
          Soc: battery,
          VehicleSpeed: speed,
          Vin: vin
        }
      }
    }
  end

  def post_event(**kwargs)
    post "/api/v1/telemetry/ingest",
         params: payload(**kwargs),
         headers: bearer_token,
         as: :json
    expect(response).to have_http_status(:created)
  end

  # ---------------------------------------------------------------------------
  # Full drive cycle
  # ---------------------------------------------------------------------------
  # Event sequence:
  #   t=0s    Gear=<invalid> (parked, no active trip) → create_empty_trip
  #   t=30s   Gear=D        (driving, no active trip) → start_trip
  #   t=60s   Gear=D        (driving, active trip)    → add_interval #1
  #   t=90s   Gear=D        (driving, active trip)    → add_interval #2
  #   t=120s  Gear=D        (driving, active trip)    → add_interval #3
  #   t=150s  Gear=P        (parked, active trip)     → complete_trip
  # ---------------------------------------------------------------------------
  describe "park → drive × 4 → park" do
    before do
      # t=0 — already parked when telemetry starts (park→park: snapshot)
      post_event(
        gear: "<invalid>",
        lat: 43.906558, lon: -78.712022,
        battery: 98.0, speed: 0,
        offset_seconds: 0
      )

      # t=30 — pull out of the driveway (park→drive: start trip)
      post_event(
        gear: "D",
        lat: 43.907000, lon: -78.711500,
        battery: 97.8, speed: 15.0,
        offset_seconds: 30
      )

      # t=60 — cruising down the road
      post_event(
        gear: "D",
        lat: 43.909200, lon: -78.709000,
        battery: 97.4, speed: 55.0,
        offset_seconds: 60
      )

      # t=90 — highway on-ramp
      post_event(
        gear: "D",
        lat: 43.912500, lon: -78.705000,
        battery: 96.9, speed: 90.0,
        offset_seconds: 90
      )

      # t=120 — highway cruise
      post_event(
        gear: "D",
        lat: 43.916800, lon: -78.699500,
        battery: 96.4, speed: 110.0,
        offset_seconds: 120
      )

      # t=150 — arrived, parked (drive→park: complete trip)
      post_event(
        gear: "P",
        lat: 43.920100, lon: -78.694000,
        battery: 95.8, speed: 0,
        offset_seconds: 150
      )
    end

    subject(:drive_trip) do
      vehicle.reload
      vehicle.trips.completed.order(:started_at).last
    end

    it "creates exactly 2 trips total" do
      expect(vehicle.reload.trips.count).to eq(2)
    end

    it "leaves the vehicle with no active trip after parking" do
      expect(vehicle.reload.active_trip).to be_nil
    end

    describe "the empty parked-snapshot trip" do
      subject(:parked_trip) { vehicle.reload.trips.order(:started_at).first }

      it "is completed with no intervals" do
        expect(parked_trip.trip_status).to eq("completed")
        expect(parked_trip.intervals.count).to eq(0)
      end

      it "records the parked location as both start and end" do
        expect(parked_trip.start_latitude).to  be_within(0.0001).of(43.906558)
        expect(parked_trip.start_longitude).to be_within(0.0001).of(-78.712022)
        expect(parked_trip.end_latitude).to    be_within(0.0001).of(43.906558)
        expect(parked_trip.end_longitude).to   be_within(0.0001).of(-78.712022)
      end
    end

    describe "the completed drive trip" do
      it "has status completed" do
        expect(drive_trip.trip_status).to eq("completed")
      end

      it "has 3 intervals (one per drive event after start_trip)" do
        expect(drive_trip.intervals.count).to eq(3)
      end

      it "starts at the first drive-event location" do
        expect(drive_trip.start_latitude).to  be_within(0.0001).of(43.907000)
        expect(drive_trip.start_longitude).to be_within(0.0001).of(-78.711500)
      end

      it "ends at the park-event location" do
        expect(drive_trip.end_latitude).to  be_within(0.0001).of(43.920100)
        expect(drive_trip.end_longitude).to be_within(0.0001).of(-78.694000)
      end

      it "records battery consumption correctly" do
        # start_battery (first D event) = 97.8, end_battery (P event) = 95.8
        expect(drive_trip.start_battery_percent).to be_within(0.01).of(97.8)
        expect(drive_trip.end_battery_percent).to   be_within(0.01).of(95.8)
        expect(drive_trip.battery_consumed_percent).to be_within(0.01).of(2.0)
      end

      it "calculates a positive distance from the intervals" do
        expect(drive_trip.distance_km).to be > 0
      end

      it "records avg and max speed from intervals" do
        # Intervals: 55, 90, 110 km/h → avg ≈ 85, max = 110
        expect(drive_trip.avg_speed_kmh).to be_within(0.1).of(85.0)
        expect(drive_trip.max_speed_kmh).to be_within(0.1).of(110.0)
      end

      it "records the correct started_at and ended_at timestamps" do
        expect(drive_trip.started_at).to  be_within(1.second).of(base_time + 30.seconds)
        expect(drive_trip.ended_at).to    be_within(1.second).of(base_time + 150.seconds)
      end

      describe "intervals in chronological order" do
        subject(:intervals) { drive_trip.intervals.chronological }

        it "stores all three interval speeds" do
          expect(intervals.map(&:speed_kmh).map(&:to_f)).to eq([55.0, 90.0, 110.0])
        end

        it "stores gear D on every interval" do
          expect(intervals.map(&:gear).uniq).to eq(["D"])
        end

        it "stores decreasing battery percentages" do
          batteries = intervals.map(&:battery_percent).map(&:to_f)
          expect(batteries).to eq([97.4, 96.9, 96.4])
        end
      end
    end
  end
end
