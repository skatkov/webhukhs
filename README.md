# Webhukhs

Webhukhs is a Rails engine for processing webhooks from various services. Engine saves webhook in database first and later processes webhook in async process.

This is a fork of [cheddar-me/munster](https://github.com/cheddar-me/munster). Original project became unmaintained, so I continued it.
## Installation

Install the gem and add to the application's Gemfile by executing:

```sh
bundle add webhukhs
```

If bundler is not being used to manage dependencies, install the gem by executing:

```sh
gem install webhukhs
```

Generate the Webhukhs migrations and initializer:

```sh
bin/rails g webhukhs:install
```

This creates database migrations and `config/initializers/webhukhs.rb`. Review the initializer to configure handlers and optional notification subscribers, then run:

```sh
bin/rails db:migrate
```

## Usage

Mount webhukhs engine in your routes.

```ruby
mount Webhukhs::Engine, at: "/webhooks"
```

Define a class for your first handler (let's call it `ExampleHandler`) and inherit it from `Webhukhs::BaseHandler`. We recommend `app/webhooks`, but any place known to autoloading will do.

```ruby
# app/webhooks/example_handler.rb
class ExampleHandler < Webhukhs::BaseHandler
  # Called asynchronously to process a stored webhook.
  def process(received_webhook)
    payload = JSON.parse(received_webhook.body, symbolize_names: true)
    # handle payload...
  end

  # Optional: verify the request signature before processing.
  # Return false to mark the webhook as failed_validation.
  def valid?(action_dispatch_request)
    action_dispatch_request.headers["X-Secret-Token"] == ENV["EXAMPLE_WEBHOOK_SECRET"]
  end

  # Optional: use a sender-supplied ID for deduplication.
  def extract_event_id_from_request(action_dispatch_request)
    action_dispatch_request.headers["X-Event-Id"] || SecureRandom.uuid
  end
end
```

Add the handler to `config/initializers/webhukhs.rb`:

```ruby
Webhukhs.configure do |config|
  config.active_handlers = {
    "example" => "ExampleHandler"
  }
end
```

Now you will be able to accept webhooks on `/webhooks/example` path.

## More Examples
- `example` folder contains a demo app with engine fully configured.
- We provide a number of webhook handlers which demonstrate certain features of Webhukhs. You will find them in `handler-examples`. 

## Requirements

This project depends on two dependencies:

- Ruby >= 3.0
- Rails >= 7.0

## Notifications

Webhukhs emits observability data through a single ActiveSupport notification: `webhukhs.event`.

The generated initializer includes a commented example subscriber. Uncomment and adapt it to route events to logs, metrics, error reporters or any other observability system. For Rails 7+ applications, you can forward error events to [Rails common error reporter](https://guides.rubyonrails.org/error_reporting.html):

```ruby
ActiveSupport::Notifications.subscribe("webhukhs.event") do |_name, _started, _finished, _id, payload|
  error = payload[:error]
  next unless error

  Rails.error.report(
    error,
    severity: payload.fetch(:severity, :error),
    context: payload.except(:error, :severity)
  )
end
```

Event payloads include structured non-sensitive metadata when available:

```ruby
{
  operation: :receive,
  outcome: :unknown_handler,
  severity: :error,
  error: error,
  service_id: "stripe",
  handler_class: "StripeHandler",
  webhook_id: 123
}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/skatkov/webhukhs.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
