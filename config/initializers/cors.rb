# Be sure to restart your server when you modify this file.

# CORS (Cross-Origin Resource Sharing) is a security mechanism enforced by browsers that blocks
# web pages from making requests to a different origin (domain, port, or protocol) than the one
# that served the page. By default, browsers restrict these cross-origin HTTP requests for safety.
#
# Since this API runs on a different port than the frontend, the browser would block all requests
# from the frontend without explicit CORS headers. The rack-cors gem adds the necessary
# Access-Control-Allow-Origin headers to responses, telling the browser which origins are
# permitted to access this API.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "http://localhost:8000"

    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
