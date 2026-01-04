# frozen_string_literal: true

Rails.application.routes.draw do
  mount Webhukhs::Engine, at: "/webhooks", as: "webhooks"
end
