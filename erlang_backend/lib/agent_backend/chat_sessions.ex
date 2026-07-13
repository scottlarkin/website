defmodule AgentBackend.ChatSessions do
  @moduledoc """
  File-backed store for shareable chat sessions (URL `/c/:id`).
  Persists under priv/chat_sessions/ and survives server restarts.
  """

  @doc "Retrieve session data for an id (or empty)"
  def get(id) when is_binary(id) do
    case File.read(session_path(id)) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, %{messages: messages}} when is_list(messages) -> %{messages: normalize_messages(messages)}
          _ -> %{messages: []}
        end

      _ ->
        %{messages: []}
    end
  end

  def get(_), do: %{messages: []}

  @doc "Save the full list of messages for a given chat id"
  def save(id, messages) when is_binary(id) and is_list(messages) do
    File.mkdir_p!(sessions_dir())

    payload = %{
      messages: messages,
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case File.write(session_path(id), Jason.encode!(payload)) do
      :ok ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("Failed to save chat session #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Generate a short, shareable, url-safe id"
  def generate_id do
    :crypto.strong_rand_bytes(6)
    |> Base.url_encode64(padding: false)
    |> String.replace(~r/[^A-Za-z0-9]/, "")
    |> String.slice(0, 8)
  end

  defp sessions_dir do
    Path.join([:code.priv_dir(:agent_backend), "chat_sessions"])
  end

  defp session_path(id), do: Path.join(sessions_dir(), "#{id}.json")

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{} = msg ->
        %{
          role: to_string(msg[:role] || msg["role"]),
          content: to_string(msg[:content] || msg["content"] || ""),
          timestamp: to_string(msg[:timestamp] || msg["timestamp"] || "")
        }

      other ->
        other
    end)
  end
end