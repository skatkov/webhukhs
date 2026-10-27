# frozen_string_literal: true

Webhukhs::Admin::Engine.routes.draw do
  resources :received_webhooks, only: [:index, :show], path: ""
  root to: "received_webhooks#index"
end
