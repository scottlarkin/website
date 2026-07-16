defmodule AgentBackend.ChatSessions do
  @moduledoc """
  File-backed store for shareable chat sessions (URL `/c/:id`).

  All mutations are serialized through a GenServer. Writes use temp+rename.
  Empty overwrites of non-empty history are refused.
  """

  use GenServer

  require Logger

  @id_re ~r/^[A-Za-z0-9]{6,12}$/

  # —— Public API ——

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "True if id is a safe session key (filesystem + URL)."
  def valid_id?(id) when is_binary(id), do: Regex.match?(@id_re, id)
  def valid_id?(_), do: false

  @doc "Retrieve session data for an id (or empty)"
  def get(id) when is_binary(id) do
    if valid_id?(id) do
      GenServer.call(__MODULE__, {:get, id})
    else
      %{messages: []}
    end
  end

  def get(_), do: %{messages: []}

  @doc "Return stored Slack thread timestamp for a chat, if any"
  def get_slack_thread_ts(id) when is_binary(id) do
    if valid_id?(id) do
      GenServer.call(__MODULE__, {:get_slack_thread_ts, id})
    else
      nil
    end
  end

  def get_slack_thread_ts(_), do: nil

  @doc "Persist Slack thread timestamp without changing messages"
  def put_slack_thread_ts(id, ts) when is_binary(id) and is_binary(ts) do
    if valid_id?(id) do
      GenServer.call(__MODULE__, {:put_slack_thread_ts, id, ts})
    else
      {:error, :invalid_id}
    end
  end

  @doc """
  Save the full list of messages for a chat id.

  Returns `:ok`, `{:error, :invalid_id}`, or `{:error, :refuse_empty}` when
  attempting to wipe an existing non-empty transcript with `[]`.
  """
  def save(id, messages) when is_binary(id) and is_list(messages) do
    if valid_id?(id) do
      GenServer.call(__MODULE__, {:save, id, messages})
    else
      {:error, :invalid_id}
    end
  end

  @doc "Generate a short, shareable, url-safe id"
  def generate_id do
    :crypto.strong_rand_bytes(6)
    |> Base.url_encode64(padding: false)
    |> String.replace(~r/[^A-Za-z0-9]/, "")
    |> String.slice(0, 8)
  end

  # —— GenServer ——

  @impl true
  def init(_opts) do
    File.mkdir_p!(sessions_dir())
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    reply =
      case read_session(id) do
        {:ok, session} -> %{messages: normalize_messages(session[:messages] || [])}
        _ -> %{messages: []}
      end

    {:reply, reply, state}
  end

  def handle_call({:get_slack_thread_ts, id}, _from, state) do
    reply =
      case read_session(id) do
        {:ok, session} -> session[:slack_thread_ts]
        _ -> nil
      end

    {:reply, reply, state}
  end

  def handle_call({:put_slack_thread_ts, id, ts}, _from, state) do
    session =
      case read_session(id) do
        {:ok, existing} -> existing
        _ -> %{messages: []}
      end

    reply = write_session(id, Map.put(session, :slack_thread_ts, ts))
    {:reply, reply, state}
  end

  def handle_call({:save, id, messages}, _from, state) do
    existing =
      case read_session(id) do
        {:ok, session} -> session
        _ -> %{}
      end

    old_messages = normalize_messages(existing[:messages] || [])

    reply =
      cond do
        messages == [] and old_messages != [] ->
          Logger.warning("ChatSessions refused empty overwrite for #{id} (had #{length(old_messages)} messages)")
          {:error, :refuse_empty}

        true ->
          payload =
            existing
            |> Map.put(:messages, messages)
            |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

          write_session(id, payload)
      end

    {:reply, reply, state}
  end

  # —— Internals ——

  def sessions_dir do
    Application.get_env(:agent_backend, :chat_sessions_dir) ||
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
    path = session_path(id)
    tmp = path <> ".tmp.#{System.unique_integer([:positive])}"

    case File.write(tmp, Jason.encode!(session)) do
      :ok ->
        case File.rename(tmp, path) do
          :ok ->
            :ok

          {:error, reason} ->
            _ = File.rm(tmp)
            Logger.error("Failed to rename chat session #{id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to write chat session #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{} = msg ->
        base = %{
          role: to_string(msg[:role] || msg["role"]),
          content: to_string(msg[:content] || msg["content"] || ""),
          timestamp: to_string(msg[:timestamp] || msg["timestamp"] || "")
        }

        if truthy?(msg[:error] || msg["error"]) do
          Map.put(base, :error, true)
        else
          base
        end

      other ->
        other
    end)
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
