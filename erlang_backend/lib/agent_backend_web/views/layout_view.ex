defmodule AgentBackendWeb.LayoutView do
  use Phoenix.View,
    root: "lib/agent_backend_web/templates",
    path: "layout",
    namespace: AgentBackendWeb

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import Phoenix.HTML, only: [raw: 1]

  @css_path "static/assets/app.css"

  def app_css do
    path = Path.join(:code.priv_dir(:agent_backend), @css_path)
    mtime = File.stat!(path).mtime
    cache_key = {:layout_app_css, mtime}

    case :persistent_term.get(cache_key, :miss) do
      :miss ->
        css = File.read!(path)
        :persistent_term.put(cache_key, css)
        css

      css ->
        css
    end
  end
end