Webhukhs.configure do |config|
  # Active Handlers are defined as hash with key as a service_id and handler class  that would handle webhook request.
  # A Handler must respond to `.new` and return an object roughly matching `Webhukhs::BaseHandler` in terms of interface.
  # Use module names (strings) here to allow the handler modules to be lazy-loaded by Rails.
  #
  # Example:
  #   {:test => "TestHandler", :inactive => "InactiveHandler"}
  config.active_handlers = {}

  # It's possible to overwrite default processing job to enahance it. As example if you want to add custom
  # locking or retry mechanism. You want to inherit that job from Webhukhs::ProcessingJob because the background
  # job also manages the webhook state.
  #
  # Example:
  #
  # class WebhookProcessingJob < Webhukhs::ProcessingJob
  #   def perform(webhook)
  #     TokenLock.with(name: "webhook-processing-#{webhook.id}") do
  #       super(webhook)
  #     end
  #   end
  #
  # In the config a string with your job' class name can be used so that the job can be lazy-loaded by Rails:
  #
  # config.processing_job_class = "WebhookProcessingJob"

  # Incoming webhooks will be written into your DB without any prior validation. By default, Webhukhs limits the
  # request body size for webhooks to 512 KiB, so that it would not be too easy for an attacker to fill your
  # database with junk. However, if you are receiving very large webhook payloads you might need to increase
  # that limit (or make it even smaller for extra security)
  #
  # config.request_body_size_limit = 2.megabytes
end

# Webhukhs emits all observability data through a single ActiveSupport::Notifications event.
# Error events are forwarded to Rails.error by default. You can customize this subscriber to
# route events to logs, metrics, error reporters or any other observability system.
ActiveSupport::Notifications.subscribe("webhukhs.event") do |_name, _started, _finished, _id, payload|
  error = payload[:error]
  next unless error

  Rails.error.report(
    error,
    severity: payload.fetch(:severity, :error),
    context: payload.except(:error, :severity)
  )
end
