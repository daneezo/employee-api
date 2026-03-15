# BrokenJob — a deliberately failing job used to test the Dead queue monitor.
#
# WHY THIS EXISTS:
# Sidekiq's "Dead" queue (also called the "morgue") holds jobs that have exhausted
# all their retries. To test our dead queue monitor, we need a job that always fails.
# This job raises an error on every attempt, and we configure it with zero retries
# so it lands in the Dead queue immediately after one failure.
#
# HOW TO USE:
#   BrokenJob.perform_later
#
# After Sidekiq processes it, the job will fail and move directly to the Dead queue
# because sidekiq_options retry: 0 disables automatic retries.
class BrokenJob < ApplicationJob
  queue_as :default

  # Disable retries so the job goes straight to the Dead queue on first failure.
  # By default, Sidekiq retries a failed job up to 25 times with exponential backoff.
  # Setting retry to 0 means: fail once, then move directly to the Dead set.
  sidekiq_options retry: 0

  # This method intentionally raises an error every time it runs.
  # The error message includes a timestamp so each failure is unique and easy to trace.
  def perform
    raise "BrokenJob intentional failure at #{Time.current} — this tests the dead queue monitor"
  end
end
