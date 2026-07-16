defmodule AgentBackendWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :agent_backend
  use Phoenix.VerifiedRoutes, router: AgentBackendWeb.Router, endpoint: AgentBackendWeb.Endpoint

  @session_options [
    store: :cookie,
    key: "_agent_backend_key",
    signing_salt: "agent_backend_salt"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug CORSPlug, origin: "*", methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  
  # Static files
  plug Plug.Static,
    at: "/",
    from: :agent_backend,
    gzip: true,
    cache: :static,
    only: ~w(assets css fonts images js robots.txt)

  plug AgentBackendWeb.Router
end
