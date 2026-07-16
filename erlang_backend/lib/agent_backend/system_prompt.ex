defmodule AgentBackend.SystemPrompt do
  @moduledoc """
  Loads the chat system prompt from prompt.md at the repo root.
  Multiline SYSTEM_PROMPT in .env is not reliable (parser + systemd truncate it).
  """

  @filename "prompt.md"

  def load(opts \\ []) do
    paths = Keyword.get(opts, :paths)

    case load_from_file(paths) do
      prompt when is_binary(prompt) and prompt != "" ->
        prompt

      _ ->
        System.get_env("SYSTEM_PROMPT") || default()
    end
  end

  def load_from_file(paths \\ nil) do
    (paths || default_paths())
    |> Enum.map(&Path.expand/1)
    |> Enum.find(&File.exists?/1)
    |> case do
      nil ->
        nil

      path ->
        case File.read(path) do
          {:ok, content} -> String.trim(content)
          _ -> nil
        end
    end
  end

  def char_count do
    load() |> String.length()
  end

  def default_paths do
    [
      Path.join(File.cwd!(), @filename),
      Path.join(File.cwd!(), "../#{@filename}"),
      Path.join(File.cwd!(), "../../#{@filename}"),
      Path.expand("../../../#{@filename}", __DIR__)
    ]
  end

  defp default do
    "You are Scott Larkin's AI assistant. Speak in first person. Do not invent employers or roles."
  end
end