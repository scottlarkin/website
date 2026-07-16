defmodule AgentBackendWeb.HealthControllerTest do
  use AgentBackendWeb.ConnCase, async: true

  test "GET /health", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200) == %{"status" => "ok", "service" => "agent-backend"}
  end
end
