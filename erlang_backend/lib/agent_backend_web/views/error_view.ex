defmodule AgentBackendWeb.ErrorView do
  use Phoenix.View,
    root: "lib/agent_backend_web",
    path: "templates/error",
    namespace: AgentBackendWeb

  import Phoenix.Component

  defp shell(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title><%= @code %> — scott</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1rem;
            background: #09090b;
            color: #e4e4e7;
            font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
            -webkit-font-smoothing: antialiased;
          }
          .wrap { max-width: 28rem; text-align: center; }
          .mark {
            width: 2.5rem; height: 2.5rem; margin: 0 auto 1.25rem;
            display: flex; align-items: center; justify-content: center;
            border-radius: 0.375rem;
            background: rgba(255, 255, 255, 0.1);
            color: #d4d4d8;
          }
          .mark svg { width: 1.125rem; height: 1.125rem; }
          h1 {
            font-size: 2.25rem;
            font-weight: 600;
            letter-spacing: -0.025em;
            color: #f4f4f5;
            margin-bottom: 0.5rem;
          }
          .lead { color: #a1a1aa; margin-bottom: 0.5rem; }
          .detail { font-size: 0.875rem; color: #52525b; margin-bottom: 1.5rem; }
          a {
            display: inline-flex;
            align-items: center;
            border-radius: 9999px;
            border: 1px solid #27272a;
            background: #18181b;
            padding: 0.375rem 1rem;
            font-size: 0.75rem;
            font-weight: 500;
            color: #d4d4d8;
            text-decoration: none;
          }
          a:hover { border-color: rgba(14, 165, 233, 0.3); color: #bae6fd; }
        </style>
      </head>
      <body>
        <div class="wrap">
          <div class="mark" aria-hidden="true">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
          </div>
          <h1><%= @code %></h1>
          <p class="lead"><%= @lead %></p>
          <p class="detail"><%= @message %></p>
          <a href="/">Back home</a>
        </div>
      </body>
    </html>
    """
  end

  def render("500.html", assigns) do
    assigns =
      assigns
      |> Map.put(:code, "500")
      |> Map.put(:lead, "My bad.")
      |> Map.put(
        :message,
        assigns[:message] ||
          "Something tripped over a cable back here. Give it a second and try again from home."
      )

    shell(assigns)
  end

  def render("404.html", assigns) do
    assigns =
      assigns
      |> Map.put(:code, "404")
      |> Map.put(:lead, "Dead end.")
      |> Map.put(
        :message,
        assigns[:message] ||
          "I don’t have a page for that. The chat’s at home if you want to ask something real."
      )

    shell(assigns)
  end

  def render("500.json", %{message: message}) do
    %{error: "Internal server error", message: message}
  end

  def render("404.json", %{message: message}) do
    %{error: "Not found", message: message}
  end

  def render("400.json", %{message: message}) do
    %{error: "Bad request", message: message}
  end
end
