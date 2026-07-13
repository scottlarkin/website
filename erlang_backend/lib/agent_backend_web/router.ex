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

  scope "/", AgentBackendWeb do
      pipe_through :browser

      live "/c/:id", ChatLive, :show
      live "/", ChatLive, :show
      live "/chat", ChatLive, :show
    end

  get "/health", AgentBackendWeb.HealthController, :index
end
