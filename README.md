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

Mount webhukhs engine in your routes.

```ruby
mount Webhukhs::Engine, at: "/webhooks"
```

Define a class for your first handler (let's call it `ExampleHandler`) and inherit it from `Webhukhs::BaseHandler`. We recommend `app/webhooks`, but any place known to autoloading will do. Add these to your `webhukhs.rb` config file:

```ruby
config.active_handlers = {
  "example" => "ExampleHandler"
}
```

## Example handlers

We provide a number of webhook handlers which demonstrate certain features of Webhukhs. You will find them in `handler-examples`. `example` folder contains a demo app with engine fully configured.

## Requirements

This project depends on two dependencies:

- Ruby >= 3.0
- Rails >= 7.0

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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/skatkov/webhukhs.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
