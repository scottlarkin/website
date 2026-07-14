defmodule AgentBackendWeb.ErrorView do
  use Phoenix.View,
    root: "lib/agent_backend_web",
    path: "templates/error",
    namespace: AgentBackendWeb

  import Phoenix.Component

  def render("500.html", assigns) do
    message = assigns[:message] || "Internal server error"
    assigns = Map.put(assigns, :message, assigns[:message] || "Internal server error")
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-900 text-white p-4">
      <div class="max-w-md mx-auto text-center">
        <h1 class="text-4xl font-bold mb-4">500</h1>
        <p class="text-gray-300 mb-4">Internal Server Error</p>
        <p class="text-sm text-gray-500"><%= @message %></p>
      </div>
    </div>
    """
  end

  def render("404.html", assigns) do
    assigns = Map.put(assigns, :message, assigns[:message] || "Not found")
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-900 text-white p-4">
      <div class="max-w-md mx-auto text-center">
        <h1 class="text-4xl font-bold mb-4">404</h1>
        <p class="text-gray-300 mb-4">Not Found</p>
        <p class="text-sm text-gray-500"><%= @message %></p>
      </div>
    </div>
    """
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