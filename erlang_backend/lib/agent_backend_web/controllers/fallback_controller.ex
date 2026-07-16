defmodule AgentBackendWeb.FallbackController do
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  @doc "Catch-all unknown paths — custom 404 without raising NoRouteError."
  def not_found(conn, _params) do
    body =
      AgentBackendWeb.ErrorView.render("404.html", %{})
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:not_found, body)
  end
end
