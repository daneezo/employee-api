# Api::EmployeesController
# Handles requests to /api/employees
# This controller lives in the Api namespace, which maps to the /api URL prefix
module Api
  class EmployeesController < ApplicationController
    # GET /api/employees
    # Returns a JSON array of all employees
    # Data is hardcoded here for now — no database required
    def index
      employees = [
        {
          id: 1,
          name: "Jane Smith",
          department: "Engineering",
          title: "Senior Developer",
          email: "jane.smith@company.com",
          phone: "(555) 123-4567",
          location: "New York"
        },
        {
          id: 2,
          name: "Michael Johnson",
          department: "Engineering",
          title: "Tech Lead",
          email: "michael.j@company.com",
          phone: "(555) 234-5678",
          location: "San Francisco"
        },
        {
          id: 3,
          name: "Emily Davis",
          department: "Marketing",
          title: "Marketing Manager",
          email: "emily.davis@company.com",
          phone: "(555) 345-6789",
          location: "Chicago"
        },
        {
          id: 4,
          name: "David Wilson",
          department: "Sales",
          title: "Account Executive",
          email: "david.wilson@company.com",
          phone: "(555) 456-7890",
          location: "Boston"
        },
        {
          id: 5,
          name: "Sarah Brown",
          department: "Human Resources",
          title: "HR Director",
          email: "sarah.brown@company.com",
          phone: "(555) 567-8901",
          location: "Austin"
        },
        {
          id: 6,
          name: "James Garcia",
          department: "Engineering",
          title: "DevOps Engineer",
          email: "james.garcia@company.com",
          phone: "(555) 678-9012",
          location: "Seattle"
        }
      ]

      # Queue a background job to log this request.
      # perform_later enqueues the job into Redis via Sidekiq — it does NOT run
      # the job right now. The Sidekiq worker process picks it up asynchronously.
      # This keeps our API response fast because we're not waiting for the logging
      # to complete before sending the response back to the client.
      EmployeeRequestJob.perform_later(Time.current.to_s)

      # render json: converts the Ruby array of hashes into a JSON response
      # Rails automatically sets the Content-Type header to application/json
      render json: employees
    end
  end
end
