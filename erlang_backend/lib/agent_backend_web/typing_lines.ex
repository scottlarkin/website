defmodule AgentBackendWeb.TypingLines do
  @moduledoc false

  @lines [
    "Checking notes…",
    "Pulling up the Trinny era…",
    "Scanning the Splyt widget days…",
    "Remembering Midrive lesson patterns…",
    "Dusting off the WoW addon story…",
    "Reviewing the skills list…",
    "Thinking about agent loops…",
    "Flipping through the CV…",
    "Gathering thoughts on London remote…",
    "Consulting the system prompt…",
    "Cross-referencing the Elixir notes…",
    "Pulling up Phoenix patterns…",
    "Scanning the TypeScript stack…",
    "Walking the React component tree…",
    "Tracing the agent loop wiring…",
    "Looking up MCP server notes…",
    "Paging through Postgres schemas…",
    "Checking the LiveView socket…",
    "Reviewing the Docker setup…",
    "Dusting off the CI pipeline…",
    "Thinking in full stack…",
    "Matching skills to the question…",
    "Pulling relevant tech from the stack…"
  ]

  def lines, do: @lines

  def random_line(other \\ nil) do
    choices =
      case other do
        nil -> @lines
        ^other when is_binary(other) -> Enum.reject(@lines, &(&1 == other))
        _ -> @lines
      end

    choices = if choices == [], do: @lines, else: choices
    Enum.random(choices)
  end
end