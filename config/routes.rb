Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/v1", module: :api, defaults: { format: :json } do
    get "health" => "health#show"

    namespace :admin do
      # admin surface (auth, servers, ...) — filled in Phase 1
    end
  end
end
