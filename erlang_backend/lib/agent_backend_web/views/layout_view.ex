defmodule AgentBackendWeb.LayoutView do
  use Phoenix.View,
    root: "lib/agent_backend_web/templates",
    path: "layout",
    namespace: AgentBackendWeb

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import Phoenix.HTML, only: [raw: 1]

  @css_path "static/assets/app.css"
  @js_path "static/assets/app.js"

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

  # Query-string cache buster so browsers don't keep stale app.js after rebuilds.
  def app_js_path do
    path = Path.join(:code.priv_dir(:agent_backend), @js_path)
    mtime = path |> File.stat!() |> Map.get(:mtime) |> erl_mtime_to_unix()
    "/assets/app.js?v=#{mtime}"
  end

  defp erl_mtime_to_unix({{y, mo, d}, {h, mi, s}}) do
    :calendar.datetime_to_gregorian_seconds({{y, mo, d}, {h, mi, s}}) -
      :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
  end
end