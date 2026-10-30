# frozen_string_literal: true

module Webhukhs
  module Admin
    # Base controller for the admin pages. Authentication is left to the host application -
    # mount the engine inside whatever guards the rest of your admin.
    class ApplicationController < ActionController::Base
      # Rails hands an engine's controllers its route helpers from an `inherited` hook, which only gets
      # installed when the app initializes - and Webhukhs may well be required before that
      include Webhukhs::Admin::Engine.routes.url_helpers

      helper Webhukhs::Admin::Engine.routes.url_helpers

      layout "webhukhs/admin/application"
      helper Assiette::Helpers
      helper Webhukhs::Admin::ViewHelper

      # Bodies and headers are whatever a sender chose to send us, so we do not let the page load
      # anything that is not ours
      content_security_policy do |policy|
        policy.default_src :none
        policy.script_src :self
        policy.style_src :self
        policy.img_src :self, :data
        policy.connect_src :self
        policy.base_uri :none
        policy.form_action :self
        policy.frame_ancestors :none
      end
    end
  end
end
