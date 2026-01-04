Webhukhs::Engine.routes.draw do
  post "/:service_id", to: "receive_webhooks#create", namespace: "webhukhs"
end
