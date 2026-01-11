# Changelog
All notable changes to this project will be documented in this file.

This format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.5.0

- Forked from [munster](https://github.com/cheddar-me/munster) and renamed to webhukhs
- Changed GitHub repository to https://github.com/skatkov/webhukhs
- Testing against rails 7.1, rails 8.0 and rails 8.1
- Ruby 3.4 used as a default testing target
- Replaced deprecated `ActiveSupport::Configurable` with `class_attribute`

## 0.4.2

- When processing a webhook, print messages to the ActiveJob logger. This allows for quicker debugging if the app does not have an error tracking service set up

## 0.4.1

- Webhook processor now requires `active_job/railtie`, instead of `active_job`. It requires GlobalID to work and that get's required only with railtie.
- Adding a state transition from `error` to `received`. Proccessing job will be enqueued automatic after this transition was executed.

## 0.4.0

- Limit's size of request body, since otherwise there can be a large attack vector where random senders can spam the database with data and cause a denial of service. With background validation, this is one of few cases where we want to reject the payload without persisting it.
- Manage's `state` of `ReceivedWebhook` from background job itself. This frees up the handler to actually do the work associated with processing only. The job will manage the rest.
- Use's `valid?` in background job instead of the controller. Most common configuration issue is an incorrectly specified signing secret, or an incorrectly implemented input validation. When these happen, it is better to allow the webhook to be reprocessed
- Use's instance methods in handlers instead of class methods, as they are shorter to define. Assume a handler module supports `.new` - with a module using singleton methods it may return `self` from `new`.
- In config, allow handlers specified as strings. Module resolution in Rails happens after config gets loaded, because config may alter to Zeitwerk load paths. To allow config to get loaded and to allow handlers to be autoloaded using Zeitwerk, handler modules have to be resolved lazily. This also permits handlers to be reloadable, like any module under Rails' autoloading control.
- Simplify's the Rails app used in tests to be small and keep it in a single file
- If a handler is willing to expose errors to the caller, let Rails rescue the error and display an error page or do whatever else is configured for Rails globally.
- Store's request headers with received webhook to allow for async validation. Run `bin/rails g webhukhs:install` to add the required migration.

## 0.3.1

- BaseHandler#expose_errors_to_sender? defaults to true now.

## 0.3.0

- state_machine_enum library was moved into its own library/gem.
- Provide handled: true attribute for Rails.error.report method, because it is required in Rails 7.0.

## 0.2.0

- Handler methods are now defined as instance methods for simplicity.
- Define service_id in initializer with active_handlers, instead of handler class.
- Use Ruby 3.0 as a base for standard/rubocop, format all code according to it.
- Use Rails common error reporter ( https://guides.rubyonrails.org/error_reporting.html )

## 0.1.0

- Initial release
