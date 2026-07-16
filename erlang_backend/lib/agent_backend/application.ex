defmodule AgentBackend.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: AgentBackend.PubSub},
      AgentBackend.ChatSessions,
      AgentBackend.AgentRuns,
      AgentBackend.SlackMonitor,
      AgentBackendWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AgentBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    AgentBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end