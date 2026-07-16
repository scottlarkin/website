defmodule AgentBackendWeb.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {AgentBackendWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Before catch-all
  get "/health", AgentBackendWeb.HealthController, :index

  scope "/", AgentBackendWeb do
    pipe_through :browser

    live "/c/:id", ChatLive, :show
    live "/", ChatLive, :show
    live "/chat", ChatLive, :show

    # Custom 404 (avoids Phoenix debug NoRouteError page in dev)
    get "/*path", FallbackController, :not_found
  end
end
