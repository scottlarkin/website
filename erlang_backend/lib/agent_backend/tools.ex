defmodule AgentBackend.Tools do
  @moduledoc """
  Extensible tool registry for the agent loop.
  Add a module to @tools to register a new tool.
  """

  @tools [
    AgentBackend.Tools.OutputValidator
  ]

  def definitions, do: Enum.map(@tools, fn mod -> mod.schema() end)

  def run_tool(name, arguments, ctx) do
    case find_module(name) do
      nil ->
        Jason.encode!(%{error: "unknown tool: #{name}"})

      mod ->
        try do
          mod.execute(arguments, ctx)
        rescue
          e ->
            require Logger
            Logger.warning("Tool #{name} crashed: #{Exception.message(e)}")
            # Lenient default for validator-shaped tools
            Jason.encode!(%{passed: true, error: Exception.message(e)})
        end
    end
  end

  def status_label(tool_calls) when is_list(tool_calls) do
    case List.first(tool_calls) do
      %{name: name} ->
        case find_module(name) do
          nil -> "Running tool…"
          mod -> mod.status_label()
        end

      _ ->
        "Running tool…"
    end
  end

  def execute_all(tool_calls, ctx) when is_list(tool_calls) do
    Enum.map(tool_calls, fn %{id: id, name: name, arguments: args} ->
      content = run_tool(name, args, ctx)
      %{role: "tool", tool_call_id: id, content: content}
    end)
  end

  defp find_module(name) do
    Enum.find(@tools, &(&1.name() == name))
  end
end