defmodule AgentBackend.Tools.Exploding do
  @moduledoc false
  @behaviour AgentBackend.Tools.Behaviour

  @impl true
  def name, do: "exploding_tool"

  @impl true
  def status_label, do: "Exploding…"

  @impl true
  def schema do
    %{
      type: "function",
      function: %{
        name: name(),
        description: "test tool",
        parameters: %{type: "object", properties: %{}, required: []}
      }
    }
  end

  @impl true
  def execute(_args, _ctx) do
    raise "boom"
  end
end
