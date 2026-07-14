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
      nil -> Jason.encode!(%{error: "unknown tool: #{name}"})
      mod -> mod.execute(arguments, ctx)
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
      content =
        case find_module(name) do
          nil ->
            Jason.encode!(%{error: "unknown tool: #{name}"})

          mod ->
            mod.execute(args, ctx)
        end

      %{role: "tool", tool_call_id: id, content: content}
    end)
  end

  def revision_needed?(tool_results) when is_list(tool_results) do
    Enum.any?(tool_results, fn %{content: content} ->
      case Jason.decode(content) do
        {:ok, %{"passed" => false}} -> true
        _ -> false
      end
    end)
  end

  defp find_module(name) do
    Enum.find(@tools, &(&1.name() == name))
  end
end