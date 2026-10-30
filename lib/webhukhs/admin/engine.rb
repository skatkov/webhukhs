# frozen_string_literal: true

module Webhukhs
  module Admin
    # Rails engine serving the admin pages and their assets.
    class Engine < ::Rails::Engine
      isolate_namespace Webhukhs::Admin

      config.eager_load_namespaces << Webhukhs::Admin

      # Rooted here rather than at the gem root, so that the views of the admin do not end up
      # on the view path of Webhukhs::Engine - which shares the gem root with us
      config.root = __dir__
      paths["app/views"] = "views"

      # Has to run before :build_middleware_stack, as Rails 8.1+ freezes the stack after it
      initializer "webhukhs_admin.assets", before: :build_middleware_stack do
        middleware.use Assiette::Server, root: Engine.root.join("assets")
      end
    end
  end
end
