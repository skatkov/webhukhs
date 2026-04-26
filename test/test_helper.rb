if ENV["SIMPLECOV"]
  require "simplecov"

  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/test/"
    add_filter "/lib/webhukhs/install_generator.rb"
    minimum_coverage 100
    minimum_coverage_by_file 100
  end
end

require_relative "test_app"
require "rails/test_help"
require "minitest/strict"
require "mutant/minitest/coverage"
require "active_support/logger"
require "stringio"

class ActiveSupport::TestCase
  # Same as "assert_changes" in Rails but for countable entities.
  # @return [*] return value of the block
  # @example
  #   assert_changes_by("Notification.count", exactly: 2) do
  #     cause_two_notifications_to_get_delivered
  #   end
  def assert_changes_by(expression, message = nil, exactly: nil, at_least: nil, at_most: nil, &block)
    # rubocop:disable Security/Eval
    exp = expression.respond_to?(:call) ? expression : -> { eval(expression.to_s, block.binding) }
    # rubocop:enable Security/Eval

    raise "either exactly:, at_least: or at_most: must be specified" unless exactly || at_least || at_most
    raise "exactly: is mutually exclusive with other options" if exactly && (at_least || at_most)
    raise "at_most: must be larger than at_least:" if at_least && at_most && at_most < at_least

    before = exp.call
    retval = assert_nothing_raised(&block)

    after = exp.call
    delta = after - before

    if exactly
      at_most = exactly
      at_least = exactly
    end

    # We do not make these an if/else since we allow both at_most and at_least
    if at_most
      error = "#{expression.inspect} changed by #{delta} which is more than #{at_most}"
      error = "#{error}. It was #{before} and became #{after}"
      error = "#{message.call}.\n" if message&.respond_to?(:call)
      error = "#{message}.\n#{error}" if message && !message.respond_to?(:call)
      assert delta <= at_most, error
    end

    if at_least
      error = "#{expression.inspect} changed by #{delta} which is less than #{at_least}"
      error = "#{error}. It was #{before} and became #{after}"
      error = "#{message.call}.\n" if message&.respond_to?(:call)
      error = "#{message}.\n#{error}" if message && !message.respond_to?(:call)
      assert delta >= at_least, error
    end

    retval
  end

  def with_overridden_singleton_method(target, method_name, implementation, &block)
    with_overridden_singleton_methods(target, {method_name => implementation}, &block)
  end

  def with_captured_info_logs(logger_owner)
    messages = []
    original_logger = logger_owner.logger
    test_logger = ActiveSupport::Logger.new(StringIO.new)
    test_logger.level = Logger::INFO
    test_logger.formatter = lambda do |_severity, _time, _progname, message|
      messages << message
      ""
    end

    logger_owner.logger = test_logger
    yield messages
  ensure
    logger_owner.logger = original_logger
  end

  def with_overridden_singleton_methods(target, methods)
    singleton_class = target.singleton_class
    original_names = methods.keys.each_with_index.to_h do |name, index|
      sanitized_name = name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      [name, :"__original_#{sanitized_name}_for_test_#{object_id}_#{index}"]
    end

    silence_warnings do
      singleton_class.class_eval do
        original_names.each do |name, original_name|
          alias_method original_name, name
        end

        methods.each do |name, override|
          define_method(name, &override)
        end
      end
    end

    yield
  ensure
    silence_warnings do
      singleton_class.class_eval do
        original_names.each do |name, original_name|
          next unless method_defined?(original_name)

          alias_method name, original_name
          remove_method original_name
        end
      end
    end
  end
end
