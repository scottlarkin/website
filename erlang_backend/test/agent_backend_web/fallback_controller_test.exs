defmodule AgentBackendWeb.FallbackControllerTest do
  use AgentBackendWeb.ConnCase, async: true

  test "unknown path returns branded 404", %{conn: conn} do
    conn = get(conn, "/this-path-does-not-exist")
    assert conn.status == 404
    body = html_response(conn, 404)
    assert body =~ "Dead end"
    assert body =~ "Back home"
  end
end
