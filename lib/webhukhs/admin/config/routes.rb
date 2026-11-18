# frozen_string_literal: true

Webhukhs::Admin::Engine.routes.draw do
  resources :received_webhooks, only: [:index, :show], path: "" do
    post :retry, on: :member
  end
  root to: "received_webhooks#index"
end
