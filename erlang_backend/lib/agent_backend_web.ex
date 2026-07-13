defmodule AgentBackendWeb do
  @moduledoc """
  The entrypoint for defining your web interface.
  """

  defmacro __using__(:controller) do
    quote do
      use Phoenix.Controller,
        namespace: AgentBackendWeb,
        formats: [json: Phoenix.View]

      import Plug.Conn
      import Phoenix.Controller
      import AgentBackendWeb.Gettext
    end
  end

  defmacro __using__(:live_view) do
    quote do
      use Phoenix.LiveView, layout: {AgentBackendWeb.LayoutView, :app}
      import AgentBackendWeb.Gettext
      import Phoenix.LiveView.Router
    end
  end

  defmacro __using__(:view) do
    quote do
      use Phoenix.View, namespace: AgentBackendWeb
      import Phoenix.Component
    end
  end

  defmacro __using__(_which) when is_atom(_which) do
    raise ArgumentError, "Unknown option for use AgentBackendWeb: #{inspect(_which)}"
  end

  def controller do
    quote do
      use Phoenix.Controller, namespace: AgentBackendWeb
      import Plug.Conn
      import Phoenix.Controller
      import AgentBackendWeb.Gettext
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {AgentBackendWeb.LayoutView, :root}
      import AgentBackendWeb.Gettext
      import Phoenix.LiveView.Router
    end
  end

  def view do
    quote do
      use Phoenix.View, namespace: AgentBackendWeb
      import Phoenix.Component
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
    end
  end

  def endpoint do
    quote do
      use Phoenix.Endpoint, otp_app: :agent_backend
      import Plug.Conn
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Component
      import AgentBackendWeb.Gettext
    end
  end
end
