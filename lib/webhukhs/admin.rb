# frozen_string_literal: true

require "assiette"
require_relative "admin/engine"

# Public namespace for Webhukhs runtime and configuration.
module Webhukhs
  # Optional, read-only admin UI for received webhooks. It gets loaded along with Webhukhs, but stays
  # out of the way until you mount {Webhukhs::Admin::Engine} - behind your own authentication.
  module Admin
    extend ActiveSupport::Autoload

    eager_autoload do
      autoload :ViewHelper, "webhukhs/admin/view_helper"
      autoload :ReceivedWebhookPresenter, "webhukhs/admin/received_webhook_presenter"
      autoload :ApplicationController, "webhukhs/admin/application_controller"
      autoload :ReceivedWebhooksController, "webhukhs/admin/received_webhooks_controller"
    end
  end
end
