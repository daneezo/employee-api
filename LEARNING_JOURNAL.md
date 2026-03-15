# Learning Journal — Employee API Project

**Author:** Daneezza Mangil
**Week of:** March 10–15, 2026
**Branch:** `DEV-18-Build-Claude-powered-Dead-queue-monitor-that-posts-to-Slack`
**Reference date:** Use this document from March 26 onward as a refresher.

---

## What We Built

A Rails API with background job processing and an AI-powered on-call automation
tool. The system monitors failed Sidekiq jobs, sends the errors to Claude for
diagnosis, and posts the analysis to Slack — replacing manual Dead queue
inspection with automated, intelligent alerting.

---

## Tool-by-Tool Breakdown

### 1. Rails API (API-Only Mode)

**What it does:**
Rails runs in API-only mode (`config.api_only = true`), which strips out views,
sessions, cookies, and other browser-oriented middleware. The result is a lean
backend that only speaks JSON.

**What we set up:**
- `GET /api/employees` — returns a hardcoded JSON array of 6 employees
- The controller lives at `app/controllers/api/employees_controller.rb`
- Routes are namespaced under `/api` in `config/routes.rb`

**What I learned:**
- API-only mode removes ~30 middleware layers compared to full Rails
- You namespace controllers under `Api::` and routes under `namespace :api` to
  get clean `/api/...` URLs
- No database is needed for the employees endpoint — data is hardcoded in the
  controller, which is fine for a learning project

**CR parallel:**
Think of this like a microservice endpoint in a CR backend — a single
responsibility service that returns data to a frontend or another service.

---

### 2. Sidekiq + Redis (Background Job Processing)

**What it does:**
Sidekiq runs as a separate process alongside Rails. When the app needs to do
slow or non-critical work (logging, emails, API calls), it pushes a job into
a Redis queue. Sidekiq picks it up and runs it in a background thread.

**What we set up:**
- `config/initializers/sidekiq.rb` — configures Redis connections for both the
  client (Rails app pushing jobs) and server (Sidekiq worker pulling jobs)
- `config/application.rb` — sets `config.active_job.queue_adapter = :sidekiq`
  so all ActiveJob classes route through Sidekiq
- `config/environments/development.rb` — adds session middleware so the Sidekiq
  Web UI works in API-only mode
- `config/routes.rb` — mounts the Sidekiq dashboard at `/sidekiq`
- Redis URL defaults to `redis://localhost:6379/0` via `ENV.fetch("REDIS_URL")`

**What I learned:**
- Sidekiq uses threads (not processes) — one Sidekiq process can handle many
  jobs concurrently, making it much more efficient than Resque or Delayed Job
- Redis is the broker: Rails serializes the job (class name + args) and pushes
  it to a Redis list; Sidekiq pops and executes
- The Sidekiq Web UI is a Rack app you mount in routes — it shows queues,
  retries, dead jobs, and real-time stats
- API-only Rails doesn't have session middleware, so you must add it manually
  for the Sidekiq dashboard to work

**CR parallel:**
This is the same pattern as any message queue system (SQS, RabbitMQ, Kafka).
The idea is the same: decouple the "request" from the "work" so the API stays
fast. In CR terms, Sidekiq is like a worker service consuming from a queue.

---

### 3. Background Jobs (ActiveJob + Sidekiq)

**What it does:**
ActiveJob is Rails' built-in abstraction for background work. You write job
classes that inherit from `ApplicationJob`, and Rails routes them to whatever
queue backend you've configured (in our case, Sidekiq).

**What we set up:**

| Job | File | Purpose |
|-----|------|---------|
| `ApplicationJob` | `app/jobs/application_job.rb` | Base class — shared config for all jobs |
| `EmployeeRequestJob` | `app/jobs/employee_request_job.rb` | Logs when the employee API is accessed |
| `BrokenJob` | `app/jobs/broken_job.rb` | Intentionally fails to test the Dead queue |

**Key details:**
- `EmployeeRequestJob.perform_later(timestamp)` is called from the employees
  controller — the request returns instantly while logging happens in the background
- `BrokenJob` uses `sidekiq_options retry: 0` to skip retries and go straight
  to the Dead queue on first failure
- By default, Sidekiq retries a failed job 25 times with exponential backoff

**What I learned:**
- `perform_later` enqueues (async), `perform_now` runs inline (sync)
- ActiveJob serializes arguments to JSON, so you can only pass simple types
  (strings, numbers, arrays, hashes) — not full Ruby objects
- The "Dead queue" (aka the morgue) is where jobs go after exhausting all
  retries. It's Sidekiq's way of saying "a human needs to look at this"
- `sidekiq_options` lets you configure per-job settings like retry count,
  queue name, and backtrace depth

**CR parallel:**
Background jobs are like Lambda functions triggered by queue events. The
BrokenJob is like a canary deployment that you intentionally break to test
your monitoring — chaos engineering at a small scale.

---

### 4. Dead Queue Monitor (AI-Powered On-Call Automation)

**What it does:**
A standalone Ruby script (`scripts/dead_queue_monitor.rb`) that:
1. Connects to Sidekiq and reads the Dead queue
2. If dead jobs exist → sends error details to Claude for analysis → posts the
   AI diagnosis to Slack
3. If no dead jobs → posts an "all clear" message to Slack

In production, this would run on a cron (e.g., every 15 minutes).

**What we set up:**
- The script boots the full Rails environment so it can access Sidekiq's config
  and Redis connection
- Uses `Sidekiq::DeadSet` from `sidekiq/api` to read the Dead queue
- Calls the Anthropic Messages API (`claude-sonnet-4-20250514`) with a
  structured SRE prompt
- Posts results to Slack via `chat.postMessage`
- All API calls use Ruby's built-in `Net::HTTP` — no extra gems

**What I learned:**
- `require "sidekiq/api"` is mandatory — the base Sidekiq gem does NOT
  auto-load API classes like `DeadSet`, `RetrySet`, and `Queue`
- The Anthropic API uses `x-api-key` header (not `Authorization: Bearer`)
  for authentication, though both work
- `.env` parsing gotcha: using `ENV[key] ||= value` silently fails if the
  key exists as an empty string `""` (empty string is truthy in Ruby). Use
  `ENV[key] = value` instead
- `File.expand_path("../../.env", __FILE__)` resolves relative to the script
  file, not the working directory — important for scripts in subdirectories
- Slack's `chat.postMessage` needs a Bot token (`xoxb-...`) with `chat:write`
  scope and the channel ID (not the channel name)

**CR parallel:**
This is a real on-call automation pattern. Instead of an engineer waking up,
opening the Sidekiq dashboard, reading the error, and deciding what to do —
Claude does the triage automatically and posts a diagnosis to the team channel.
It's the same concept as PagerDuty + Runbook automation, but with AI analysis.

---

### 5. Environment Variable Management

**What it does:**
Secrets (API keys, tokens) are stored in a `.env` file that is loaded by the
script at runtime and excluded from version control.

**What we set up:**
- `.env` in the project root with three keys:
  - `ANTHROPIC_API_KEY` — for Claude API calls
  - `SLACK_BOT_TOKEN` — for Slack posting
  - `SLACK_CHANNEL_ID` — target channel for alerts
- `.gitignore` already had `/.env*` — Rails generates this by default
- The monitor script has a hand-rolled `.env` parser (no dotenv gem)

**What I learned:**
- Never commit secrets to Git — even "test" keys. `.env*` in `.gitignore` is
  the first line of defense
- Ruby's `ENV.fetch("KEY") { abort "message" }` is better than `ENV["KEY"]`
  because it fails fast with a clear error instead of silently returning `nil`
- Hand-rolling a `.env` parser is ~10 lines of Ruby: read lines, skip comments
  and blanks, split on `=`, strip quotes, set `ENV`
- In production, you'd use real secret management (AWS Secrets Manager, Vault,
  or platform env vars) instead of `.env` files

**CR parallel:**
Same as any secrets management — environment-specific config that should never
be in source control. The `.env` file pattern is universal across languages
(Node has dotenv, Python has python-dotenv, Ruby has the dotenv gem).

---

## Key Automation Insights

### Why AI + Queue Monitoring Matters
Traditional monitoring tells you "something broke." AI-powered monitoring tells
you "here's what broke, why it likely happened, and what to do about it." The
difference is response time — instead of an engineer spending 20 minutes reading
stack traces, they get a pre-digested diagnosis in Slack within seconds.

### The Architecture Pattern
```
[Sidekiq Dead Queue]
        |
        v
[Monitor Script] ---> [Claude API] ---> analyze errors
        |                                     |
        v                                     v
   [Slack API] <-----------------------------|
        |
        v
  [On-call team sees diagnosis in Slack]
```

### What Makes This Production-Ready (and What Doesn't)
**Ready:**
- Fail-fast on missing env vars
- Structured error reports for Claude (not raw dumps)
- Slack-formatted output (bold, emoji, timestamps)
- Timeout handling for Claude API calls

**Not yet production-ready:**
- No authentication on the Sidekiq Web dashboard
- No error handling if Redis is down
- No deduplication (running twice reports the same dead jobs twice)
- No automatic clearing of dead jobs after reporting
- Should run on a scheduler (cron, Heroku Scheduler, Sidekiq-Cron)

### Debugging Lessons
1. **401 from Anthropic API** — turned out to be the `.env` parser using `||=`
   instead of `=`. Empty string is truthy in Ruby, so `ENV["KEY"] ||= "value"`
   is a no-op if `KEY` is already set to `""`.
2. **"uninitialized constant Sidekiq::DeadSet"** — `sidekiq/api` must be
   required explicitly. The base gem only loads worker/client code.
3. **Sidekiq dashboard 500 in API-only mode** — API-only Rails strips session
   middleware, but the Sidekiq Web UI needs it. Fix: add `ActionDispatch::Cookies`
   and `ActionDispatch::Session::CookieStore` middleware in development.rb.

---

## Quick Reference Commands

```bash
# Start Redis (required for Sidekiq)
redis-server

# Start Sidekiq worker process
bundle exec sidekiq

# Start Rails server
bundle exec rails server

# Open Rails console
bundle exec rails console

# Enqueue the broken job (from Rails console)
BrokenJob.perform_later

# Run the dead queue monitor
ruby scripts/dead_queue_monitor.rb

# Check the Sidekiq dashboard
open http://localhost:3000/sidekiq
```

---

## File Map

```
employee-api/
├── app/
│   ├── controllers/
│   │   └── api/
│   │       └── employees_controller.rb   # GET /api/employees
│   └── jobs/
│       ├── application_job.rb            # Base job class
│       ├── employee_request_job.rb       # Logs API access (background)
│       └── broken_job.rb                 # Intentionally failing test job
├── config/
│   ├── application.rb                    # Sidekiq as ActiveJob adapter
│   ├── routes.rb                         # API routes + Sidekiq dashboard
│   ├── environments/
│   │   └── development.rb                # Session middleware for Sidekiq UI
│   └── initializers/
│       └── sidekiq.rb                    # Redis connection config
├── scripts/
│   └── dead_queue_monitor.rb             # AI-powered dead queue monitor
├── .env                                  # Secrets (gitignored)
├── .gitignore                            # Includes /.env*
├── Gemfile                               # Rails, Sidekiq, Puma, rack-cors
└── LEARNING_JOURNAL.md                   # This file
```
