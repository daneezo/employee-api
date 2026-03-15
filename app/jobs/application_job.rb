# ApplicationJob is the base class that all background jobs in this app inherit from.
# It plays the same role as ApplicationController does for controllers or
# ApplicationRecord does for models — it's a single place to define shared behavior
# (like retry logic, error handling, or queue defaults) that applies to every job.
#
# Under the hood, ApplicationJob inherits from ActiveJob::Base, which is Rails'
# built-in framework for declaring and running background jobs. ActiveJob provides
# a unified API so you can swap queue backends (Sidekiq, Resque, Delayed Job, etc.)
# without changing any of your job classes.
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encounter a deadlock.
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying record is no longer available.
  # discard_on ActiveJob::DeserializationError
end
