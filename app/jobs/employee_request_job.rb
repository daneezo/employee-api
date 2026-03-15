# EmployeeRequestJob — a background job that logs when the employee directory is accessed.
#
# WHY USE A BACKGROUND JOB FOR LOGGING?
# In a real application, logging/auditing might involve writing to a database,
# calling an external analytics service, or sending a notification. These operations
# can be slow and shouldn't block the API response. By moving them to a background
# job, the controller responds instantly while Sidekiq processes the work separately.
#
# HOW IT WORKS:
# 1. The controller calls EmployeeRequestJob.perform_later(...) — this serializes
#    the job arguments and pushes them into a Redis queue (takes ~1ms).
# 2. Sidekiq, running in a separate process, picks the job off the Redis queue.
# 3. Sidekiq calls #perform with the original arguments and executes the work.
# 4. If the job fails, Sidekiq automatically retries it (up to 25 times by default).
class EmployeeRequestJob < ApplicationJob
  # Use the "default" queue. Sidekiq processes queues by priority — you could
  # create separate queues like "critical" or "low" for different job types.
  queue_as :default

  # This method runs in the background, NOT during the web request.
  # +timestamp+ is the time the API request was made (passed in by the controller).
  def perform(timestamp)
    Rails.logger.info(
      "[EmployeeRequestJob] Employee directory accessed at #{timestamp}"
    )
  end
end
