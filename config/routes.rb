Rails.application.routes.draw do
  get 'home/index'
  resources :users

  # You can have the root of your site routed with "root"
  root 'home#index'
end
