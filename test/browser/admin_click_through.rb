# frozen_string_literal: true

require "test_helper"
require "ferrum"
require "puma"
require "puma/server"

# Clicks through the admin in a real Chrome, so that what the request tests cannot see - the JS, the
# CSP letting it run, assets resolving under the mount point - is exercised too. Not part of `rake test`,
# run it with `rake test:browser`.
class AdminClickThrough < ActiveSupport::TestCase
  # The app answers from Puma threads with connections of their own, which would not see rows
  # created inside a test transaction
  self.use_transactional_tests = false

  PAGE_SIZE = Webhukhs::Admin::ReceivedWebhooksController::PAGE_SIZE

  def self.server
    @server ||= Puma::Server.new(WebhukhsTestApp, nil, min_threads: 0, max_threads: 4, log_writer: Puma::LogWriter.null).tap do |server|
      server.add_tcp_listener("127.0.0.1", 0)
      server.run
      Minitest.after_run { server.stop(true) }
    end
  end

  setup do
    @base_url = "http://127.0.0.1:#{self.class.server.connected_ports.first}/admin"
    @console_errors = []
    # GitHub's Ubuntu runners do not let Chrome set up its sandbox
    browser_options = ENV["CI"] ? {"no-sandbox" => nil} : {}
    @browser = Ferrum::Browser.new(timeout: 10, js_errors: true, browser_options: browser_options)
    @browser.on("Log.entryAdded") { |params| @console_errors << params.dig("entry", "text") if params.dig("entry", "level") == "error" }
    @browser.on("Runtime.consoleAPICalled") { |params| @console_errors << params["args"].map { |arg| arg["value"] }.join(" ") if params["type"] == "error" }
    @browser.page.command("Log.enable")
  end

  teardown do
    failed = @browser.network.traffic.filter_map do |exchange|
      "#{exchange.response.status} #{exchange.request.url}" if exchange.response && exchange.response.status >= 400
    end
    @browser.quit
    Webhukhs::ReceivedWebhook.delete_all

    assert_empty failed, "Requests failed"
    assert_empty @console_errors, "The browser logged errors"
  end

  def create_webhook(**attributes)
    Webhukhs::ReceivedWebhook.create!(
      handler_module_name: "WebhookTestHandler",
      handler_event_id: SecureRandom.uuid,
      status: "processed",
      body: '{"event":"thing.happened"}',
      **attributes
    )
  end

  def visit(path)
    @browser.go_to(@base_url + path)
  end

  def wait_for(what, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until (result = yield)
      flunk "Timed out waiting for #{what}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    result
  end

  def click_and_wait_for_page(node)
    url = @browser.current_url
    label = node.text.strip
    # Ferrum clicks at the node's coordinates as they are, and a click below the fold hits nothing
    node.scroll_into_view
    node.click
    wait_for("#{label.inspect} to leave #{url}") { @browser.current_url != url }
    # The URL changes as soon as the navigation commits, while the new document may still be parsing
    wait_for("the page after #{label.inspect} to load") { @browser.evaluate("document.readyState") == "complete" }
    @browser.network.wait_for_idle
  end

  # In one evaluate, so that auto-refresh swapping the table cannot pull the nodes out from under us
  def texts(selector)
    @browser.evaluate("Array.from(document.querySelectorAll(#{selector.to_json}), (node) => node.textContent.trim())")
  end

  test "lists, sorts, filters and pages through webhooks" do
    PAGE_SIZE.times { |i| create_webhook(handler_event_id: "evt-#{i}", created_at: i.minutes.ago) }
    create_webhook(handler_event_id: "the-failed-one", status: "error", created_at: 2.days.ago)

    visit ""
    assert_equal "Received webhooks", @browser.at_css("h1").text
    # The stylesheet must have made it through the CSP - unstyled, the header would not be a flexbox
    assert_equal "flex", @browser.evaluate("getComputedStyle(document.querySelector('.admin-header')).display")
    assert_equal PAGE_SIZE, @browser.css("tbody tr").length
    assert_equal "the-failed-one", texts("tbody tr td:nth-child(5)").first

    click_and_wait_for_page(@browser.at_xpath("//th/a[contains(., 'Received')]"))
    assert_includes @browser.current_url, "direction=desc"
    assert_equal "evt-0", texts("tbody tr td:nth-child(5)").first

    click_and_wait_for_page(@browser.at_xpath("//th/a[contains(., 'Received')]"))
    assert_includes @browser.current_url, "direction=asc"
    assert_equal "the-failed-one", texts("tbody tr td:nth-child(5)").first

    # Not Ferrum's Node#select: it blanks the select by assigning it `undefined` first, which
    # left it blank on the Chromium snapshot CI got
    @browser.execute(<<~JS)
      const select = document.querySelector("select[name=status]")
      select.value = "error"
      select.dispatchEvent(new Event("change", {bubbles: true}))
    JS
    assert_equal "error", @browser.evaluate("document.querySelector('select[name=status]').value")
    click_and_wait_for_page(@browser.at_css("form.filters input[type=submit]"))
    assert_equal ["the-failed-one"], texts("tbody tr td:nth-child(5)")
    # The sort survives filtering
    assert_includes @browser.current_url, "direction=asc"

    click_and_wait_for_page(@browser.at_xpath("//form//a[text()='Clear']"))
    assert_equal "Any status", @browser.evaluate("document.querySelector('select[name=status]').selectedOptions[0].text")

    click_and_wait_for_page(@browser.at_css("a[rel=next]"))
    assert_equal 1, @browser.css("tbody tr").length
    click_and_wait_for_page(@browser.at_css("a[rel=prev]"))
    assert_equal PAGE_SIZE, @browser.css("tbody tr").length
  end

  test "opens a webhook by clicking anywhere on its row" do
    webhook = create_webhook(handler_event_id: "evt-clicked")

    visit ""
    # The status cell is not a link, but the row link stretched over it takes the click
    click_and_wait_for_page(@browser.at_css("tbody tr td:nth-child(4)"))

    assert_equal "#{@base_url}/#{webhook.id}", @browser.current_url
    assert_includes @browser.at_css("h1").text, "WebhookTestHandler"
  end

  test "switches between the pretty and the as-sent body" do
    webhook = create_webhook(body: '{"event":"thing.happened","data":{"id":1}}')

    visit "/#{webhook.id}"
    pretty = -> { @browser.evaluate("document.getElementById('body-pretty').hidden") == false }
    raw = -> { @browser.evaluate("document.getElementById('body-raw').hidden") == false }
    assert pretty.call
    refute raw.call

    @browser.at_css("#body-tab-raw").click
    wait_for("the as-sent tab") { raw.call }
    refute pretty.call
    assert_equal "true", @browser.at_css("#body-tab-raw").attribute("aria-selected")
    assert_equal '{"event":"thing.happened","data":{"id":1}}', @browser.at_css("#body-raw code").text

    @browser.at_css("#body-tab-raw").focus
    @browser.keyboard.type(:Left)
    wait_for("the arrow key to go back to the pretty tab") { pretty.call }
    assert_equal "body-tab-pretty", @browser.evaluate("document.activeElement.id")
  end

  test "copies to the clipboard" do
    webhook = create_webhook(handler_event_id: "evt-to-copy")

    visit "/#{webhook.id}"
    # Headless Chrome has no clipboard to grant, so we only check that the right text gets handed to it
    @browser.execute("navigator.clipboard.writeText = (text) => { window.copied = text; return Promise.resolve() }")

    @browser.at_css("button.btn-copy[data-copy='evt-to-copy']").click
    wait_for("the copy button to flash") { @browser.at_css("button.btn-copy.copied[data-copy='evt-to-copy']") }
    assert_equal "evt-to-copy", @browser.evaluate("window.copied")

    @browser.at_css("button.btn-copy-panel").click
    wait_for("the body to be copied") { @browser.evaluate("window.copied") != "evt-to-copy" }
    assert_equal JSON.pretty_generate({"event" => "thing.happened"}), @browser.evaluate("window.copied")
  end

  test "shows bodies that are not JSON, or too large to display" do
    form = create_webhook(body: "event=paid&amount=12.50")
    large = create_webhook(body: "x" * (Webhukhs::Admin::ReceivedWebhookPresenter::DISPLAY_LIMIT + 1))

    visit "/#{form.id}"
    assert_equal "This body is not valid JSON, so it is shown as it was sent", @browser.at_css(".flash.alert").text
    assert_equal "event=paid&amount=12.50", @browser.at_css("pre.body-raw code").text
    assert_empty @browser.css("[role=tab]")

    visit "/#{large.id}"
    assert_equal "The body was 256 KB, display is truncated", @browser.at_css(".flash.alert").text
  end

  test "picks up new webhooks while auto-refresh is on, and remembers the switch" do
    create_webhook(handler_event_id: "evt-before")

    visit ""
    switch = -> { @browser.evaluate("document.getElementById('auto-refresh').checked") }
    refute switch.call
    @browser.at_css("label.switch").click
    wait_for("the switch to turn on") { switch.call }

    create_webhook(handler_event_id: "evt-arrived")
    # One poll interval, with some slack
    wait_for("the new webhook to show up", timeout: 8) { texts("tbody tr td:nth-child(5)").include?("evt-arrived") }
    assert_equal ["evt-arrived", "evt-before"], texts("tbody tr td:nth-child(5)")

    visit ""
    assert switch.call, "The switch should stay on after a reload"
    # After a page load only the timer refetches, so this one has to come in through a poll
    create_webhook(handler_event_id: "evt-polled")
    wait_for("the polled webhook to show up", timeout: 8) { texts("tbody tr td:nth-child(5)").include?("evt-polled") }
    @browser.at_css("label.switch").click
    wait_for("the switch to turn off") { !switch.call }
  end
end
