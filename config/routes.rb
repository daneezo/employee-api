# Require Sidekiq's built-in web UI.
# Since this is an API-only Rails app (no ActionDispatch::Session middleware),
# we need to add session middleware manually so the Sidekiq Web UI can work
# (it uses sessions for CSRF protection).
require "sidekiq/web"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Mount the Sidekiq Web UI at /sidekiq
  # This dashboard lets you monitor queues, see running/failed/scheduled jobs,
  # retry failed jobs, and view real-time stats — all powered by data in Redis.
  # In production, you should protect this route with authentication (e.g., Devise).
  mount Sidekiq::Web => "/sidekiq"

  # Namespace all endpoints under /api
  # This groups related controllers and keeps the URL structure clean
  namespace :api do
    # GET /api/employees -> Api::EmployeesController#index
    get "employees", to: "employees#index"
  end
end
