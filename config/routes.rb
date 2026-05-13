Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/v1", module: :api, defaults: { format: :json } do
    get "health" => "health#show"

    scope module: :auth do
      post   "auth/magic_link" => "magic_links#create",  as: :auth_magic_link
      post   "auth/exchange"   => "magic_links#exchange", as: :auth_exchange
      get    "auth/keys"       => "keys#index",          as: :auth_keys
      delete "auth/keys/:id"   => "keys#destroy",        as: :auth_key
    end

    namespace :admin do
      scope module: :auth do
        post   "auth/magic_link" => "magic_links#create",  as: :auth_magic_link
        post   "auth/exchange"   => "magic_links#exchange", as: :auth_exchange
        get    "auth/keys"       => "keys#index",          as: :auth_keys
        delete "auth/keys/:id"   => "keys#destroy",        as: :auth_key
      end
    end
  end
end
