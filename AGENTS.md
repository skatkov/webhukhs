# AGENTS.md

This document helps agents work effectively in the Munster codebase.

## Project Overview

Munster is a Rails engine that provides a webhook endpoint for receiving and processing webhooks from various services. Webhooks are stored first, then processed asynchronously in a background job.

**Technology Stack:**
- Ruby >= 3.0
- Rails >= 7.0
- Minitest for testing
- StandardRB for linting

## Essential Commands

### Development
```bash
bundle install          # Install dependencies
bundle exec rake        # Run tests and linting (default task)
bundle exec rake test   # Run tests only
bundle exec rake standard  # Run StandardRB linter
bundle exec rake format  # Format code (standardrb + magic_frozen_string_literal)
```

### Testing Against Multiple Rails Versions Locally

Use Appraisal to test against different Rails versions:

```bash
# Generate gemfiles for each Rails version
bundle exec appraisal install

# Run tests against specific Rails version
bundle exec appraisal rails-7.1 bundle exec rake test
bundle exec appraisal rails-8.0 bundle exec rake test
bundle exec appraisal rails-8.1 bundle exec rake test

# Run tests against all Rails versions
bundle exec appraisal bundle exec rake test

# Run with deprecation warnings enabled
RAILS_DEPRECATIONS_TO_STDOUT=true bundle exec appraisal rails-8.0 bundle exec rake test
```

### Running Specific Tests
```bash
bundle exec rake test test/munster_test.rb  # Run specific test file
```

### Gem Operations
```bash
bundle exec rake install  # Install gem locally
bundle exec rake release  # Create git tag and publish to rubygems.org
```

## Code Organization

### Main Library (`lib/munster/`)
- `base_handler.rb` - Base class for webhook handlers
- `models/received_webhook.rb` - ActiveRecord model for stored webhooks
- `controllers/receive_webhooks_controller.rb` - Webhook receiver endpoint
- `jobs/processing_job.rb` - ActiveJob for async webhook processing
- `engine.rb` - Rails engine definition
- `version.rb` - Version number

### Testing (`test/`)
- `munster_test.rb` - Main integration tests
- `test_helper.rb` - Test setup and custom assertions
- `test_app.rb` - Minimal Rails app for testing
- `test-webhook-handlers/` - Handler implementations for testing

### Examples (`handler-examples/`)
Contains real-world webhook handler examples:
- `customer_io_handler.rb` - Customer.io webhooks with HMAC signature validation
- `revolut_business_v1_handler.rb` - Revolut V1 API
- `revolut_business_v2_handler.rb` - Revolut V2 API
- `starling_payments_handler.rb` - Starling Bank payments

### Example App (`example/`)
Complete Rails application demonstrating Munster integration.

## Naming Conventions and Style Patterns

### Code Style
- **Linting**: Uses StandardRB (Ruby 3.0+)
- **Frozen String Literal**: All files MUST start with `# frozen_string_literal: true`
- **Formatting**: `bundle exec rake format` runs standardrb and magic_frozen_string_literal
- **No RuboCop config**: `.rubocop.yml` only exists for editor support; CI runs StandardRB directly

### Handler Naming
- Handler classes should follow descriptive naming: `CustomerIoHandler`, `RevolutBusinessV1Handler`
- In config, handlers can be specified as strings or classes to support lazy loading:
  ```ruby
  config.active_handlers = {
    "service-1" => "MyHandler",        # String for lazy loading
    "service-2" => MyHandlerClass      # Class reference
  }
  ```

### Database Conventions
- Table: `received_webhooks`
- Columns:
  - `handler_event_id` - Unique event ID for deduplication
  - `handler_module_name` - Handler class name
  - `status` - State machine state (received, processing, processed, failed_validation, error, skipped)
  - `body` - Binary request body
  - `request_headers` - JSON headers for async validation

## Webhook Handler Pattern

### Creating a Handler
Inherit from `Munster::BaseHandler` and implement these instance methods:

```ruby
class MyHandler < Munster::BaseHandler
  # Optional: Override validation (runs in background job)
  def valid?(action_dispatch_request)
    # Return false to reject webhook
    true
  end

  # Required: Process the webhook
  def process(webhook)
    json = JSON.parse(webhook.body, symbolize_names: true)
    # Your processing logic here
  end

  # Optional: Extract unique event ID for deduplication
  def extract_event_id_from_request(action_dispatch_request)
    action_dispatch_request.headers["X-Event-Id"] || SecureRandom.uuid
  end

  # Optional: Control error exposure to webhook sender
  def expose_errors_to_sender?
    false  # Hide errors and return 200 with error message
  end

  # Optional: Deactivate handler (for load shedding)
  def active?
    true
  end
end
```

### Handler Configuration
Register handlers in `config/initializers/munster.rb`:
```ruby
Munster.configure do |config|
  config.active_handlers = {
    "my-service" => "MyHandler"
  }
  config.processing_job_class = CustomJob  # Optional custom job class
  config.request_body_size_limit = 1.megabyte  # Default: 512.kilobytes
end
```

### Error Context
Add error context for error reporting (Honeybadger, Sentry, etc.):
```ruby
Munster.configure do |config|
  config.error_context = {
    appsignal: { namespace: "webhooks" }
  }
end
```

## Testing Approach

### Test Structure
- Uses `ActionDispatch::IntegrationTest` for webhook endpoint testing
- Background jobs are processed synchronously in tests via `perform_enqueued_jobs`
- Custom assertion: `assert_changes_by` for counting changes

### Common Test Patterns
```ruby
# Test webhook reception
post "/munster/test", params: body_json, headers: {"CONTENT_TYPE" => "application/json"}
assert_response 200

# Check job enqueuing
assert_enqueued_jobs 1, only: Munster::ProcessingJob do
  post "/munster/test", params: body_json
end

# Process background jobs
perform_enqueued_jobs

# Verify webhook state
webhook = Munster::ReceivedWebhook.last!
assert_predicate webhook, :processed?
```

### Test Webhook Helpers
Test handlers in `test/test-webhook-handlers/` demonstrate various scenarios:
- Validation (valid/invalid)
- Error handling (exposed/concealed errors)
- Inactive handlers
- Event ID extraction
- Private/route param preservation

### Rails Version Compatibility
Test app in `test/test_app.rb` sets `active_support.cache_format_version` dynamically based on Rails version (7.1 for Rails 7.1+).
CI tests against Rails 7.1, 8.0, and 8.1. Ruby 4.0 is only tested with Rails 8.x due to dependency compatibility.

## Important Gotchas

### Async Validation
Validation runs in the **background job**, not in the controller. This allows reprocessing webhooks after fixing signing secret misconfigurations. The `valid?` method receives a reconstructed ActionDispatch::Request.

### Deduplication
Webhooks are deduplicated by the combination of `handler_module_name` + `handler_event_id`. Override `extract_event_id_from_request` to extract the unique ID from the webhook payload or headers.

### Handler Instantiation
Handlers are instantiated via `.new` on every webhook reception. Use instance methods, not class methods. If using a module, it should return self from `.new`.

### Route Params Preservation
When mounting Munster under a parametrized route (e.g., `/webhooks/:user_id/:service_id`), route params are preserved and available in `webhook.request.params` during processing. This is critical for multi-tenant setups.

### Request Body Size Limit
Default limit is 512 KB. Webhooks exceeding this limit are rejected without persistence to prevent DoS attacks.

### State Machine Transitions
The `ReceivedWebhook` model uses `state_machine_enum` for status management:
- `received` → `processing` → `processed`/`failed_validation`/`error`/`skipped`
- `error` → `received` (allows reprocessing)
- Transitions trigger job enqueuing automatically

### Error Reporting
Uses Rails common error reporter. Errors are reported with `handled: true` to avoid bubbling up to the error tracking service unnecessarily. Custom context is added via `config.error_context`.

### Lazy Handler Loading
Handlers specified as strings in config are lazy-loaded via `constantize`. This is necessary because Rails' Zeitwerk autoloading hasn't loaded application files when initializers run.

## Database Migrations

### Installation
Run in consuming application:
```bash
bin/rails g munster:install
```

This creates:
- Migration to create `received_webhooks` table
- Migration to add `request_headers` column
- Initializer file at `config/initializers/munster.rb`

### Key Indexes
- Unique index on `(handler_module_name, handler_event_id)` for deduplication
- Index on `status` for backfill processing

### Body Column Type
The `body` column uses `:binary` type (not `:jsonb`) because webhook payloads may be malformed, incomplete, or non-JSON.

## Mounting the Engine

In your `config/routes.rb`:
```ruby
mount Munster::Engine, at: "/webhooks"
```

Default route: `POST /webhooks/:service_id`

For custom routing with parameters:
```ruby
post "/incoming-webhooks/:user_id/:service_id" => "munster/receive_webhooks#create"
```

## CI/CD

GitHub Actions workflow (`.github/workflows/main.yml`):
- Tests on Ruby 3.3.0 (all Rails versions) and 4.0 (Rails 8.x only)
- Tests against Rails 7.1, 8.0, and 8.1 using Appraisal
- Executes `bundle exec rake` (tests + linting) for each Ruby/Rails combination
- Runs on push to `main` and on pull requests
- `RAILS_DEPRECATIONS_TO_STDOUT=true` enables deprecation warnings in output
- Note: Ruby 4.0 only tests Rails 8.x due to Nokogiri compatibility issues with Rails 7.1
