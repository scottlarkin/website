defmodule AgentBackend.ChatSessions do
  @moduledoc """
  File-backed store for shareable chat sessions (URL `/c/:id`).
  Persists under priv/chat_sessions/ and survives server restarts.
  """

  @doc "Retrieve session data for an id (or empty)"
  def get(id) when is_binary(id) do
    case read_session(id) do
      {:ok, session} -> %{messages: normalize_messages(session[:messages] || [])}
      _ -> %{messages: []}
    end
  end

  @doc "Return stored Slack thread timestamp for a chat, if any"
  def get_slack_thread_ts(id) when is_binary(id) do
    case read_session(id) do
      {:ok, session} -> session[:slack_thread_ts]
      _ -> nil
    end
  end

  @doc "Persist Slack thread timestamp without changing messages"
  def put_slack_thread_ts(id, ts) when is_binary(id) and is_binary(ts) do
    session =
      case read_session(id) do
        {:ok, existing} -> existing
        _ -> %{messages: []}
      end

    write_session(id, Map.put(session, :slack_thread_ts, ts))
  end

  def get(_), do: %{messages: []}

  @doc "Save the full list of messages for a given chat id"
  def save(id, messages) when is_binary(id) and is_list(messages) do
    session =
      case read_session(id) do
        {:ok, existing} -> existing
        _ -> %{}
      end

    payload =
      session
      |> Map.put(:messages, messages)
      |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

    write_session(id, payload)
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

  defp read_session(id) do
    case File.read(session_path(id)) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, session} when is_map(session) -> {:ok, session}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp write_session(id, session) when is_map(session) do
    File.mkdir_p!(sessions_dir())

    case File.write(session_path(id), Jason.encode!(session)) do
      :ok ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("Failed to save chat session #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

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