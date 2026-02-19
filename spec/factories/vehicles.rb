FactoryBot.define do
  factory :vehicle do
    association :user
    sequence(:tesla_vehicle_id) { |n| n.to_s }
    sequence(:vin) { |n| "LRW3E1FA4PC9#{n.to_s.rjust(5, '0')}" }
    display_name      { "Test Tesla" }
    telemetry_active  { true }
    telemetry_synced  { false }
  end
end
