Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Namespace all endpoints under /api
  # This groups related controllers and keeps the URL structure clean
  namespace :api do
    # GET /api/employees -> Api::EmployeesController#index
    get "employees", to: "employees#index"
  end
end
