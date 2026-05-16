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
      delete "auth/account"    => "account#destroy",     as: :auth_account
    end

    resources :servers, only: %i[index] do
      member do
        post  :join
        patch "me" => "servers/me#update"
        get   "hall-of-fame" => "servers/hall_of_fame#show"
      end

      scope module: :servers do
        resources :players, only: %i[show], param: :handle
      end
    end

    resources :worlds, only: %i[show] do
      member { post :join }
      scope module: :worlds do
        get  "map" => "map#index"
        get  "trade-ledger" => "trade_ledger#index"
        get  "archive" => "archive#show"
        resources :regions, only: %i[show] do
          get :adjacent, on: :member
        end
        resources :ruins, only: %i[index]
        resources :nodes, only: %i[index show]
        resources :wonders, only: %i[index]
      end
    end

    resources :kingdoms, only: %i[show] do
      member { post :build }
      scope module: :kingdoms do
        resources :build_orders,    only: %i[destroy], path: "build"
        resources :training_orders, only: %i[create destroy], path: "train"
        resources :armies,          only: %i[index]
        resources :battles,         only: %i[index]
        resources :caravans,        only: %i[create]
        resource :wonder, only: %i[show create destroy] do
          post :repair
          post :milestone
        end
      end
    end

    resources :armies, only: %i[show] do
      member do
        post :march
        post :recall
        post :split
        post :rename
        post :merge
      end
    end

    resources :battles, only: %i[show]

    namespace :admin do
      scope module: :auth do
        post   "auth/magic_link" => "magic_links#create",  as: :auth_magic_link
        post   "auth/exchange"   => "magic_links#exchange", as: :auth_exchange
        get    "auth/keys"       => "keys#index",          as: :auth_keys
        delete "auth/keys/:id"   => "keys#destroy",        as: :auth_key
      end

      resources :servers, only: %i[index create update destroy] do
        scope module: :servers do
          resources :admins,      only: %i[index create destroy]
          resources :invitations, only: %i[index create destroy]
          resources :members,     only: %i[index]
          resources :worlds,      only: %i[index create]
        end
      end

      resources :worlds, only: %i[show update] do
        member { post :cancel }
        scope module: :worlds do
          resources :invitations, only: %i[index create destroy]
          resources :battles,     only: %i[index]
        end
      end
    end
  end
end
