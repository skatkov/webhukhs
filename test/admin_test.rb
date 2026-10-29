# frozen_string_literal: true

require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  cover "Webhukhs::Admin*"

  self.app = WebhukhsTestApp

  teardown { Webhukhs::ReceivedWebhook.delete_all }

  def create_webhook(**attributes)
    Webhukhs::ReceivedWebhook.create!(
      handler_module_name: "WebhookTestHandler",
      handler_event_id: SecureRandom.uuid,
      status: "processed",
      body: '{"event":"thing.happened"}',
      **attributes
    )
  end

  def listed_event_ids
    css_select("table.admin-table tbody tr td:nth-child(5) code").map(&:text)
  end

  test "lists webhooks by descending id regardless of received time by default" do
    create_webhook(handler_event_id: "first", created_at: 1.day.ago)
    create_webhook(handler_event_id: "last", created_at: 2.days.ago)

    get "/admin"

    assert_response :ok
    assert_equal ["last", "first"], listed_event_ids
    # The whole row is the link, so it has to be there in the first cell
    assert_select "tbody tr td:first-child a.row-link[href^='/admin/']", count: 2
    assert_select "th a.sort-link[href=?]", "/admin/?direction=asc", text: "Id ▼"
    assert_select "th a", count: 1
    assert_select "th a.sort-link span.sort-arrow", text: "▼", count: 1
    assert_equal ["Id ▼", "Received", "Handler", "Status", "Event id", "Updated"], css_select("th").map(&:text)
  end

  test "sorts by id in ascending order when requested" do
    create_webhook(handler_event_id: "first", created_at: 1.day.ago)
    create_webhook(handler_event_id: "last", created_at: 2.days.ago)

    get "/admin", params: {direction: "asc"}

    assert_equal ["first", "last"], listed_event_ids
    assert_select "th a.sort-link[href=?]", "/admin/?direction=desc", text: "Id ▲"
  end

  test "abbreviates UUID ids without changing the underlying id" do
    {
      "01a1895c-806f-7518-a388-c6c6a4496e51" => "01a1895c-..-6e51",
      "01A1895C-806F-7518-A388-C6C6A4496E51" => "01A1895C-..-6E51",
      "f47ac10b-58cc-4372-a567-0e02b2c3d479" => "f47ac10b-..-d479"
    }.each do |id, label|
      presenter = Webhukhs::Admin::ReceivedWebhookPresenter.new(Struct.new(:id).new(id))

      assert_equal label, presenter.display_id
      assert_equal id, presenter.id
    end
  end

  test "leaves non-UUID ids unchanged" do
    uuid = "01a1895c-806f-7518-a388-c6c6a4496e51"
    ids = [123, "manual-id", "prefix#{uuid}", "#{uuid}suffix", "#{uuid}\n"]
    groups = uuid.split("-")
    groups.each_index do |index|
      [groups[index][0...-1], "#{groups[index]}0", "g#{groups[index][1..]}"].each do |invalid_group|
        ids << groups.each_with_index.map { |group, i| (i == index) ? invalid_group : group }.join("-")
      end
    end

    ids.each do |id|
      presenter = Webhukhs::Admin::ReceivedWebhookPresenter.new(Struct.new(:id).new(id))
      assert_equal id.to_s, presenter.display_id
    end
  end

  test "keeps the full id in the row link and hover text" do
    webhook = create_webhook

    get "/admin"

    assert_select "a.row-link[href=?][title=?][aria-label=?]", "/admin/#{webhook.id}", webhook.id.to_s, webhook.id.to_s do
      assert_select "code.cell-id", text: webhook.id.to_s
    end
  end

  test "ignores legacy sort columns in either direction" do
    create_webhook(handler_event_id: "z", status: "skipped", created_at: 1.day.ago, updated_at: 1.hour.ago)
    create_webhook(handler_event_id: "a", handler_module_name: "PrivateHandler", status: "error", created_at: 2.days.ago, updated_at: 2.hours.ago)

    %w[created_at updated_at handler_module_name handler_event_id status].each do |column|
      get "/admin", params: {sort: column, direction: "desc"}
      assert_equal ["a", "z"], listed_event_ids, column

      get "/admin", params: {sort: column, direction: "asc"}
      assert_equal ["z", "a"], listed_event_ids, column
    end
  end

  test "offers an auto-refresh switch, off by default, for the listing it refetches" do
    create_webhook

    get "/admin"

    assert_select ".page-heading label.switch input#auto-refresh[type=checkbox][role=switch]:not([checked])"
    # admin.js swaps this element for the one in the refetched page
    assert_select "#received-webhooks table.admin-table tbody tr", count: 1
    assert_select "#received-webhooks nav.pagination"
  end

  test "serves the index at the engine root" do
    create_webhook(handler_event_id: "at-root")

    get "/admin"

    assert_response :ok
    assert_equal ["at-root"], listed_event_ids
    assert_select ".admin-header a[href=?]", "/admin/", text: "Received webhooks"
    assert_select "form.filters[action=?]", "/admin/"
  end

  test "ignores unsupported sort columns and directions" do
    # Creation order differs from received time, so the fallback must use id.
    create_webhook(handler_event_id: "new", created_at: 1.day.ago, status: "skipped", body: "z")
    create_webhook(handler_event_id: "old", created_at: 2.days.ago, status: "error", body: "a")

    get "/admin", params: {sort: "body", direction: "sideways"}

    assert_response :ok
    assert_equal ["old", "new"], listed_event_ids
  end

  test "filters by handler and status, and treats blank filters as no filter" do
    create_webhook(handler_event_id: "test-processed")
    create_webhook(handler_event_id: "test-error", status: "error")
    create_webhook(handler_event_id: "private-processed", handler_module_name: "PrivateHandler")

    get "/admin", params: {handler: "WebhookTestHandler"}
    assert_equal ["test-error", "test-processed"], listed_event_ids.sort

    get "/admin", params: {status: "error"}
    assert_equal ["test-error"], listed_event_ids

    get "/admin", params: {handler: "", status: ""}
    assert_equal 3, listed_event_ids.length
  end

  test "offers every configured handler and status as a filter" do
    get "/admin", params: {handler: "PrivateHandler", direction: "asc"}

    handlers = css_select("select[name=handler] option").map { |option| option["value"] }
    assert_equal ["", *Webhukhs.configuration.active_handlers.values.uniq.sort], handlers
    assert_select "select[name=handler] option[value='']", text: "Any handler"
    assert_select "select[name=status] option[value='']", text: "Any status"
    # Filtering and clearing the filters keep the direction, without a sort column
    assert_select "form.filters input[name=direction][value=asc]"
    assert_select "form.filters input[name=sort]", count: 0
    assert_select "form.filters a[href=?]", "/admin/?direction=asc", text: "Clear"
    assert_select "select[name=handler] option[selected]", text: "PrivateHandler"

    statuses = css_select("select[name=status] option").map { |option| option["value"] }
    assert_equal ["", *Webhukhs::ReceivedWebhook.statuses.keys], statuses
  end

  test "lists a handler configured as a class once, by name" do
    original_handlers = Webhukhs.configuration.active_handlers
    Webhukhs.configuration.active_handlers = {a: WebhookTestHandler, b: "WebhookTestHandler"}

    get "/admin"

    handlers = css_select("select[name=handler] option").map { |option| option["value"] }
    assert_equal ["", "WebhookTestHandler"], handlers
  ensure
    Webhukhs.configuration.active_handlers = original_handlers
  end

  test "paginates by #{Webhukhs::Admin::ReceivedWebhooksController::PAGE_SIZE}" do
    page_size = Webhukhs::Admin::ReceivedWebhooksController::PAGE_SIZE
    (page_size + 1).times { |i| create_webhook(handler_event_id: "evt-#{i}", created_at: i.minutes.ago) }

    get "/admin", params: {direction: "asc"}
    assert_equal page_size, listed_event_ids.length
    assert_equal (0...page_size).map { |i| "evt-#{i}" }, listed_event_ids
    assert_select "a[rel=prev]", count: 0
    assert_select "a[rel=next][href=?]", "/admin/?direction=asc&page=2"

    get "/admin", params: {direction: "asc", page: 2}
    assert_equal ["evt-#{page_size}"], listed_event_ids
    assert_select "a[rel=next]", count: 0
    assert_select "a[rel=prev][href=?]", "/admin/?direction=asc&page=1"
  end

  test "loads one row past the page and no more" do
    page_size = Webhukhs::Admin::ReceivedWebhooksController::PAGE_SIZE
    (page_size + 5).times { create_webhook }

    loaded = 0
    counter = ->(*, payload) { loaded += payload[:record_count] if payload[:class_name] == "Webhukhs::ReceivedWebhook" }
    ActiveSupport::Notifications.subscribed(counter, "instantiation.active_record") do
      get "/admin"
    end

    assert_equal page_size + 1, loaded
  end

  test "shows no next page when the last page is exactly full" do
    Webhukhs::Admin::ReceivedWebhooksController::PAGE_SIZE.times { create_webhook }

    get "/admin"

    assert_select "a[rel=next]", count: 0
  end

  test "treats a page below 1 as the first page" do
    create_webhook(handler_event_id: "only")

    get "/admin", params: {page: -3}

    assert_equal ["only"], listed_event_ids
    assert_select "a[rel=prev]", count: 0
  end

  test "keeps filters but drops the page and legacy sort when reversing the order" do
    get "/admin", params: {page: 3, sort: "updated_at", handler: "PrivateHandler", status: "error"}

    assert_select "th a.sort-link[href=?]", "/admin/?direction=asc&handler=PrivateHandler&status=error"
  end

  test "says so when there is nothing to list" do
    get "/admin"

    assert_select "div.table-scroll > table.admin-table > thead > tr > th", count: 6
    assert_select "table.admin-table > tbody > tr > td.empty[colspan='6']", text: "No records."
  end

  test "colors the status badges" do
    {
      "processed" => "status-ok",
      "error" => "status-bad",
      "failed_validation" => "status-bad",
      "received" => "status-waiting",
      "processing" => "status-waiting",
      "skipped" => "status-neutral"
    }.each do |status, css_class|
      assert_equal css_class, Webhukhs::Admin::ReceivedWebhookPresenter.new(create_webhook(status: status)).status_class
    end
  end

  test "shows a JSON body pretty-printed, with the body as sent in a second tab" do
    create_webhook(handler_event_id: "decoy", body: "not this one")
    webhook = create_webhook(body: '{"event":"thing.happened","data":{"id":1}}')

    get "/admin/#{webhook.id}"

    assert_response :ok
    assert_select "h1", text: /WebhookTestHandler/
    assert_select ".breadcrumb a[href=?]", "/admin/", text: "Received webhooks"
    assert_select "[role=tab][aria-selected=true]", text: "Pretty"
    assert_select "[role=tab][aria-selected=false]", text: "As sent"
    # assert_select squashes whitespace, which is the very thing under test here
    assert_equal JSON.pretty_generate({"event" => "thing.happened", "data" => {"id" => 1}}),
      css_select("#body-pretty:not([hidden]) code").text
    assert_equal '{"event":"thing.happened","data":{"id":1}}', css_select("#body-raw[hidden] code").text
    assert_select ".flash.alert", count: 0
  end

  test "shows a body that is not JSON as sent, replacing invalid UTF-8" do
    webhook = create_webhook(body: "event=thing&broken=\xFF".b)

    get "/admin/#{webhook.id}"

    assert_response :ok
    assert_select "[role=tab]", count: 0
    assert_select ".flash.alert", text: /not valid JSON/
    assert_select "pre.body-raw code", text: "event=thing&broken=\u{FFFD}"
  end

  test "shows a body over the display limit cut off, without pretty-printing it" do
    limit = Webhukhs::Admin::ReceivedWebhookPresenter::DISPLAY_LIMIT
    json = %({"padding":"#{"x" * limit}"})
    webhook = create_webhook(body: json)

    get "/admin/#{webhook.id}"

    assert_response :ok
    assert_select "[role=tab]", count: 0
    assert_select ".flash.alert", text: "The body was 256 KB, display is truncated"
    assert_equal json.byteslice(0, limit), css_select("pre.body-raw code").text
  end

  test "displays a body of exactly the display limit in full" do
    limit = Webhukhs::Admin::ReceivedWebhookPresenter::DISPLAY_LIMIT
    presenter = Webhukhs::Admin::ReceivedWebhookPresenter.new(create_webhook(body: "x" * limit))

    assert_false presenter.truncated?
    assert_equal limit, presenter.body_text.bytesize
    assert_true Webhukhs::Admin::ReceivedWebhookPresenter.new(create_webhook(body: "x" * (limit + 1))).truncated?
  end

  test "replaces a character the display limit cuts through" do
    limit = Webhukhs::Admin::ReceivedWebhookPresenter::DISPLAY_LIMIT
    presenter = Webhukhs::Admin::ReceivedWebhookPresenter.new(create_webhook(body: ("x" * (limit - 1)) + "é"))

    assert_equal ("x" * (limit - 1)) + "\u{FFFD}", presenter.body_text
  end

  test "decodes the body without touching the stored bytes" do
    webhook = create_webhook(body: "caf\xC3\xA9".b).reload
    presenter = Webhukhs::Admin::ReceivedWebhookPresenter.new(webhook)

    assert_equal "café", presenter.body_text
    assert_equal Encoding::UTF_8, presenter.body_text.encoding
    assert_equal Encoding::BINARY, webhook.body.encoding
  end

  test "shows the request headers sorted by name, with the path parameters as JSON" do
    webhook = create_webhook(request_headers: {
      "HTTP_X_SIGNATURE" => "sig",
      "CONTENT_TYPE" => "application/json",
      "action_dispatch.request.path_parameters" => {"service_id" => "test"}
    })

    get "/admin/#{webhook.id}"

    rows = css_select("table.admin-table thead:has(th:contains('Header')) + tbody tr").map do |row|
      row.css("td").map(&:text)
    end
    assert_equal [
      ["CONTENT_TYPE", "application/json"],
      ["HTTP_X_SIGNATURE", "sig"],
      ["action_dispatch.request.path_parameters", '{"service_id":"test"}']
    ], rows
  end

  test "shows webhooks stored before headers were recorded" do
    webhook = create_webhook(request_headers: nil)

    get "/admin/#{webhook.id}"

    assert_response :ok
    assert_select "td.empty[colspan='2']", text: "No records."
  end

  test "renders copy buttons for the identifiers" do
    webhook = create_webhook(handler_event_id: "evt_123")

    get "/admin/#{webhook.id}"

    assert_select "button.btn-copy[type=button][title='Copy to clipboard'][data-copy=?]", webhook.id.to_s
    assert_select "button.btn-copy[data-copy=?]", "evt_123"
  end

  test "locks the pages down with a content security policy" do
    get "/admin"

    assert_equal "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; " \
      "connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
      response.headers["Content-Security-Policy"]
  end

  test "serves its own assets, fingerprinted, from under the mount point" do
    get "/admin"

    assert_select "link[rel=stylesheet][href^='/admin/admin.css?s='][integrity^='sha256-']"
    assert_select "script[type=module][src^='/admin/admin.js?s='][integrity^='sha256-']"

    get "/admin/admin.css"
    assert_response :ok
    assert_includes response.body, ".admin-table"
  end
end
