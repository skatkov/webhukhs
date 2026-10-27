# Webhukhs

Webhukhs is a Rails engine for processing webhooks from various services. Engine saves webhook in database first and later processes webhook in async process.

This is a fork of [cheddar-me/munster](https://github.com/cheddar-me/munster). Original project became unmaintained, so I continued it.
## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add webhukhs

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install webhukhs

## Usage

Generate migrations and initializer file.

`bin/rails g webhukhs:install`

Mount webhukhs engine in `config/routes.rb` file (simple approach, with only one dynamic route showing up in `rails routes`)

```ruby
mount Webhukhs::Engine, at: "/webhooks"
```

Advanced mounting approach (all webhooks paths will be shown in `rails routes`)

```ruby
Webhukhs.configuration.active_handlers.each_key do |service_id|
  post "/webhooks/#{service_id}",
    to: "webhukhs/receive_webhooks#create",
    defaults: { service_id: service_id },
    as: :"#{service_id.tr('-', '_')}_webhook"
end
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

Add the handler to your `webhukhs.rb` config file:

```ruby
Webhukhs.configure do |config|
  config.active_handlers = {
    "example" => "ExampleHandler"
  }
end
```

Now you will be able to accept webhooks on `/webhooks/example` path.

## Admin

Webhukhs comes with a read-only admin for looking at the webhooks you have received: a sortable,
filterable list, and a page per webhook with its body (pretty-printed when it is JSON) and the
request headers it arrived with. It is not loaded by default - require it in your Gemfile (it has to be
loaded before the app boots, so `config/routes.rb` is too late):

```ruby
gem "webhukhs", require: ["webhukhs", "webhukhs/admin"]
```

and mount it:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Webhukhs::Admin::Engine, at: "/admin/webhooks"
end
```

The admin does no authentication of its own, and webhook bodies tend to carry personal data and
secrets - so mount it behind whatever guards the rest of your admin. For example, with Devise:

```ruby
authenticate :user, ->(user) { user.admin? } do
  mount Webhukhs::Admin::Engine, at: "/admin/webhooks"
end
```

or with HTTP basic auth:

```ruby
webhukhs_admin = Rack::Builder.new do
  use Rack::Auth::Basic do |username, password|
    ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("ADMIN_USER")) &
      ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("ADMIN_PASSWORD"))
  end
  run Webhukhs::Admin::Engine
end
mount webhukhs_admin, at: "/admin/webhooks"
```

The admin brings its own CSS and JS, served by [Assiette](https://github.com/julik/assiette) from
inside the engine - it does not touch your asset pipeline (Propshaft, Sprockets or anything else) and needs
no build step.

To try it out, run `bin/dev` from a checkout of this repository. It starts the app in `example`
with some webhooks seeded, and the admin at http://localhost:3000/admin/webhukhs.

The list defaults to descending ID order using the existing primary-key index; no extra migration is
needed. Click **Received** to sort by timestamp instead.

**We strongly recommend against UUIDv4 primary keys.** Use UUIDv7 or auto-incrementing integer IDs
instead. UUIDv4 IDs are random, so sorting by ID does not reflect creation time, and inserts have
poorer index locality. Webhukhs generates UUIDv7 when Ruby supports it, but falls back to UUIDv4
otherwise; use a Ruby with UUIDv7 support if you need UUID primary keys.

## More Examples
- `example` folder contains a demo app with the engine and the admin fully configured - run it with `bin/dev`.
- We provide a number of webhook handlers which demonstrate certain features of Webhukhs. You will find them in `handler-examples`.

## Requirements

- Ruby >= 3.1
- Rails >= 7.2

## Error reporter

This gem uses [Rails common error reporter](https://guides.rubyonrails.org/error_reporting.html) to report any possible error to services like Honeybadger, Appsignal, Sentry and etc. Most of those services already support this common interface, if not - it's not that hard to add this support on your own.

It's possible to provide additional context for every error. e.g.

```ruby
Webhukhs.configure do |config|
  config.error_context = { appsignal: { namespace: "webhooks" } }
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

The admin also has a click-through test in a real (headless) Chrome, which `rake test` leaves out.
Run it with `bundle exec rake test:browser` - it needs Chrome or Chromium installed, and finds it
by itself or through `BROWSER_PATH`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/skatkov/webhukhs.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
