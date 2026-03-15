# WHAT IS REDIS?
# Redis is an open-source, in-memory data store. Think of it as a super-fast
# key-value database that lives entirely in RAM. It's commonly used for caching,
# session storage, and as a message broker.
#
# WHY DOES SIDEKIQ NEED REDIS?
# Sidekiq uses Redis as its job queue. When your app enqueues a background job,
# Sidekiq serializes the job data (class name, arguments) and pushes it into a
# Redis list. The Sidekiq worker process then pops jobs off that list and executes
# them. Redis is perfect for this because:
#   - It's extremely fast (sub-millisecond operations)
#   - It supports atomic list operations (push/pop) for reliable queuing
#   - It persists data to disk, so jobs survive Redis restarts
#   - It can handle thousands of jobs per second

# Configure the Redis connection for the Sidekiq server (the worker process).
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

# Configure the Redis connection for the Sidekiq client (your Rails app).
# The client pushes jobs into Redis; the server pulls them out.
Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
