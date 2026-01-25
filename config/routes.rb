Rails.application.routes.draw do
  # Devise routes
  devise_for :users

  # Root path
  root "home#index"

  # Public key hosting for Tesla partner verification
  get "/.well-known/appspecific/com.tesla.3p.public-key.pem",
      to: "well_known#public_key"

  # Tesla OAuth routes
  get "/auth/tesla/callback", to: "tesla_sessions#create"
  get "/auth/failure", to: "tesla_sessions#failure"
  delete "/tesla/disconnect", to: "tesla_sessions#destroy"

  # Virtual key pairing callback
  get "/tesla/paired", to: "tesla_sessions#paired"

  # Refresh token with Fleet API audience
  post "/tesla/refresh_fleet_token", to: "tesla_sessions#refresh_fleet_token"

  # Dashboard (requires login)
  get "/dashboard", to: "dashboard#index"

  # Vehicles management (requires login)
  resources :vehicles, only: [:index, :show] do
    member do
      post :refresh
    end
    resource :telemetry, only: [:create, :destroy], controller: 'vehicles/telemetry' do
      get :errors
    end
  end

  # Settings (requires login)
  get "/settings", to: "settings#index"

  # Tesla Partner Account Registration
  namespace :tesla do
    post "partner/register", to: "partner#register"
    get "partner/status", to: "partner#status"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
