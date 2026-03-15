#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# Dead Queue Monitor — an on-call automation tool
# =============================================================================
#
# This script connects to Sidekiq's Dead queue (the "morgue"), reads any jobs
# that have permanently failed, sends the error details to Claude for analysis,
# and posts the results to a Slack channel.
#
# In production, you would run this on a cron schedule (e.g., every 15 minutes)
# so your on-call team gets proactive alerts with AI-powered diagnosis instead
# of having to manually inspect the Sidekiq dashboard.
#
# REQUIRED ENVIRONMENT VARIABLES:
#   ANTHROPIC_API_KEY  — API key for calling Claude (https://console.anthropic.com)
#   SLACK_BOT_TOKEN    — Slack Bot OAuth token with chat:write scope
#   SLACK_CHANNEL_ID   — The Slack channel ID to post messages to
#   REDIS_URL          — (optional) Redis connection URL, defaults to localhost
#
# USAGE:
#   ANTHROPIC_API_KEY=sk-... SLACK_BOT_TOKEN=xoxb-... SLACK_CHANNEL_ID=C0123... ruby scripts/dead_queue_monitor.rb
# =============================================================================

# ---------------------------------------------------------------------------
# Load environment variables from the .env file in the project root.
# This is a lightweight approach using plain Ruby — no extra gems needed.
# Each line in .env is expected to be in KEY=value format. Lines starting
# with # are treated as comments and blank lines are skipped.
# Values are set unconditionally so the .env file is the source of truth
# when running this script locally. Surrounding quotes are stripped so both
# KEY=value and KEY="value" work.
# ---------------------------------------------------------------------------
dotenv_path = File.expand_path("../../.env", __FILE__)
if File.exist?(dotenv_path)
  File.readlines(dotenv_path).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")

    key, value = line.split("=", 2)
    next unless key && value

    # Strip surrounding single or double quotes if present (e.g., KEY="value")
    value = value.strip.gsub(/\A["']|["']\z/, "")
    ENV[key.strip] = value
  end
end

# ---------------------------------------------------------------------------
# Boot the Rails environment so we can access Sidekiq's configuration and
# ActiveJob classes. This loads config/application.rb, initializers (including
# our Sidekiq Redis config), and all job classes.
# ---------------------------------------------------------------------------
require_relative "../config/environment"

# Sidekiq's core gem only loads the worker/client code by default.
# The API classes (DeadSet, RetrySet, Queue, etc.) live in "sidekiq/api"
# and must be required explicitly.
require "sidekiq/api"

# Net::HTTP is Ruby's built-in HTTP client — no extra gems needed.
# We use it for both the Anthropic API and the Slack API calls.
require "net/http"
require "uri"
require "json"

# ---------------------------------------------------------------------------
# SECTION 1: Validate environment variables
# ---------------------------------------------------------------------------
# Fail fast with a clear message if any required secrets are missing.
# This prevents confusing errors later in the script.
ANTHROPIC_API_KEY = ENV.fetch("ANTHROPIC_API_KEY") do
  abort "[FATAL] Missing ANTHROPIC_API_KEY environment variable. Get one at https://console.anthropic.com"
end

SLACK_BOT_TOKEN = ENV.fetch("SLACK_BOT_TOKEN") do
  abort "[FATAL] Missing SLACK_BOT_TOKEN environment variable. Create a Slack app at https://api.slack.com/apps"
end

SLACK_CHANNEL_ID = ENV.fetch("SLACK_CHANNEL_ID") do
  abort "[FATAL] Missing SLACK_CHANNEL_ID environment variable. Use Slack's channel info to find the ID."
end

# ---------------------------------------------------------------------------
# SECTION 2: Read the Sidekiq Dead queue
# ---------------------------------------------------------------------------
# Sidekiq stores permanently failed jobs in a sorted set in Redis called the
# "dead" set. The Sidekiq::DeadSet class provides a Ruby API to read it.
# A job ends up here after exhausting all retries — it's Sidekiq's way of
# saying "I give up, a human needs to look at this."
puts "[Monitor] Connecting to Sidekiq Dead queue..."
dead_set = Sidekiq::DeadSet.new
dead_jobs = dead_set.to_a

puts "[Monitor] Found #{dead_jobs.size} dead job(s)."

# ---------------------------------------------------------------------------
# SECTION 3: Handle the "all clear" case
# ---------------------------------------------------------------------------
# If the Dead queue is empty, post a green status message to Slack so the
# on-call team knows the monitor is running and everything is healthy.
if dead_jobs.empty?
  puts "[Monitor] No dead jobs found. Posting all-clear to Slack..."

  all_clear_message = [
    ":white_check_mark: *Dead Queue Monitor — All Clear*",
    "",
    "No failed jobs in the Sidekiq Dead queue.",
    "Checked at: #{Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")}"
  ].join("\n")

  # --- Post to Slack ---
  # The Slack chat.postMessage API expects a JSON body with channel and text.
  # We use the Bot token for authentication via the Authorization header.
  uri = URI("https://slack.com/api/chat.postMessage")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri.path)
  request["Authorization"] = "Bearer #{SLACK_BOT_TOKEN}"
  request["Content-Type"] = "application/json; charset=utf-8"
  request.body = JSON.generate({
    channel: SLACK_CHANNEL_ID,
    text: all_clear_message
  })

  response = http.request(request)
  result = JSON.parse(response.body)

  if result["ok"]
    puts "[Monitor] All-clear posted to Slack successfully."
  else
    warn "[Monitor] Slack API error: #{result["error"]}"
  end

  exit 0
end

# ---------------------------------------------------------------------------
# SECTION 4: Build a summary of dead jobs for Claude
# ---------------------------------------------------------------------------
# We extract the key details from each dead job: the job class, arguments,
# error class, error message, and when it failed. This gives Claude enough
# context to diagnose the failures without sending raw Redis data.
puts "[Monitor] Building error summary for Claude analysis..."

job_summaries = dead_jobs.map.with_index(1) do |job, index|
  # Each entry in the DeadSet is a Sidekiq::SortedEntry with job metadata.
  # The item hash contains the serialized job details from Redis.
  item = job.item
  [
    "--- Dead Job ##{index} ---",
    "Job Class   : #{item["wrapped"] || item["class"]}",
    "Arguments   : #{item["args"].inspect}",
    "Queue       : #{item["queue"]}",
    "Error Class : #{item["error_class"]}",
    "Error Message: #{item["error_message"]}",
    "Failed At   : #{Time.at(item["failed_at"]).strftime("%Y-%m-%d %H:%M:%S %Z") rescue "unknown"}",
    "Retry Count : #{item["retry_count"] || 0}",
    ""
  ].join("\n")
end

error_report = job_summaries.join("\n")
puts "[Monitor] Error report:\n#{error_report}"

# ---------------------------------------------------------------------------
# SECTION 5: Send the error report to Claude for analysis
# ---------------------------------------------------------------------------
# We call the Anthropic Messages API with Claude Sonnet to analyze the dead
# jobs. The prompt asks Claude to act as an SRE and provide:
#   - A root cause analysis for each failure
#   - Recommended actions to fix or prevent recurrence
#   - Priority/severity assessment
#
# This turns raw error data into actionable on-call guidance.
puts "[Monitor] Sending error report to Claude for analysis..."

anthropic_uri = URI("https://api.anthropic.com/v1/messages")
anthropic_http = Net::HTTP.new(anthropic_uri.host, anthropic_uri.port)
anthropic_http.use_ssl = true
# Allow extra time for Claude to generate a thorough analysis.
anthropic_http.read_timeout = 60

anthropic_request = Net::HTTP::Post.new(anthropic_uri.path)
anthropic_request["x-api-key"] = ANTHROPIC_API_KEY
anthropic_request["anthropic-version"] = "2023-06-01"
anthropic_request["Content-Type"] = "application/json"

# The prompt is structured to get a concise, actionable Slack-friendly response.
anthropic_request.body = JSON.generate({
  model: "claude-sonnet-4-20250514",
  max_tokens: 1024,
  messages: [
    {
      role: "user",
      content: <<~PROMPT
        You are an experienced Site Reliability Engineer reviewing failed background jobs
        from a Ruby on Rails application using Sidekiq. Below is a report of jobs that have
        permanently failed and landed in the Dead queue.

        Analyze each failure and provide:
        1. A brief root cause analysis
        2. Recommended fix or next steps
        3. Severity level (Critical / High / Medium / Low)

        Keep your response concise and formatted for Slack (use *bold* for emphasis and
        bullet points). Do not use markdown headers (#) — use *bold text* instead.

        Here are the dead jobs:

        #{error_report}
      PROMPT
    }
  ]
})

anthropic_response = anthropic_http.request(anthropic_request)
anthropic_result = JSON.parse(anthropic_response.body)

# Extract Claude's analysis text from the API response.
# The Messages API returns content as an array of content blocks.
if anthropic_response.code.to_i != 200
  warn "[Monitor] Anthropic API error (HTTP #{anthropic_response.code}): #{anthropic_result}"
  claude_analysis = "_Claude analysis unavailable — API returned HTTP #{anthropic_response.code}. Raw error report is included above._"
else
  claude_analysis = anthropic_result.dig("content", 0, "text") || "No analysis returned."
end

puts "[Monitor] Claude analysis received (#{claude_analysis.length} chars)."

# ---------------------------------------------------------------------------
# SECTION 6: Post the analysis to Slack
# ---------------------------------------------------------------------------
# We compose a Slack message that includes both the raw error count and
# Claude's AI-powered analysis so the on-call engineer gets the full picture.
slack_message = [
  ":rotating_light: *Dead Queue Monitor — #{dead_jobs.size} Failed Job(s) Detected*",
  "",
  "*Checked at:* #{Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")}",
  "",
  "*AI Analysis (Claude):*",
  claude_analysis
].join("\n")

puts "[Monitor] Posting analysis to Slack..."

slack_uri = URI("https://slack.com/api/chat.postMessage")
slack_http = Net::HTTP.new(slack_uri.host, slack_uri.port)
slack_http.use_ssl = true

slack_request = Net::HTTP::Post.new(slack_uri.path)
slack_request["Authorization"] = "Bearer #{SLACK_BOT_TOKEN}"
slack_request["Content-Type"] = "application/json; charset=utf-8"
slack_request.body = JSON.generate({
  channel: SLACK_CHANNEL_ID,
  text: slack_message
})

slack_response = slack_http.request(slack_request)
slack_result = JSON.parse(slack_response.body)

if slack_result["ok"]
  puts "[Monitor] Analysis posted to Slack successfully!"
else
  warn "[Monitor] Slack API error: #{slack_result["error"]}"
  exit 1
end

puts "[Monitor] Done."
