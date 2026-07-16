defmodule AgentBackendWeb.TypingLines do
  @moduledoc false

  # No trailing ellipsis — the UI already shows animated dots beside these.
  @lines [
    "Checking notes",
    "Reviewing the skills list",
    "Thinking about agent loops",
    "Flipping through the CV",
    "Consulting the system prompt",
    "Pulling up Phoenix patterns",
    "Scanning the TypeScript stack",
    "Walking the React component tree",
    "Tracing the agent loop wiring",
    "Looking up MCP server notes",
    "Paging through Postgres schemas",
    "Checking the LiveView socket",
    "Reviewing the Docker setup",
    "Dusting off the CI pipeline",
    "Matching skills to the question",
    "Pulling relevant tech from the stack",
    "Rereading the deployment notes",
    "Tracing a WebSocket reconnect path",
    "Skimming the architecture sketch",
    "Double-checking the stack choice",
    "Opening the project footnotes",
    "Lining up a straight answer"
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
