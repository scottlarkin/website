defmodule AgentBackendWeb.HealthController do
  use Phoenix.Controller,
    namespace: AgentBackendWeb,
    formats: [json: Phoenix.View]

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.Controller, only: [json: 2, put_new_layout: 2, put_new_view: 2]

  def index(conn, _params) do
    json(conn, %{status: "ok", service: "agent-backend"})
  end
end
