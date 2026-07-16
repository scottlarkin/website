defmodule AgentBackend.SlackMonitor do
  @moduledoc """
  Async Slack monitoring: one thread per chat in the monitor channel,
  errors in a separate channel.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def log_user_message(chat_id, content) when is_binary(chat_id) and is_binary(content) do
    cast({:user_message, chat_id, content})
  end

  def log_assistant_message(chat_id, content) when is_binary(chat_id) and is_binary(content) do
    cast({:assistant_message, chat_id, content})
  end

  def log_error(chat_id, kind, detail)
      when is_binary(chat_id) and is_atom(kind) and is_binary(detail) do
    cast({:error, chat_id, kind, detail})
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_cast({:user_message, chat_id, content}, state) do
    if slack().enabled?() do
      thread_ts = ensure_thread(chat_id)
      post_thread_reply(thread_ts, "*User:* #{content}")
    end

    {:noreply, state}
  end

  def handle_cast({:assistant_message, chat_id, content}, state) do
    if slack().enabled?() and content != "" do
      thread_ts = ensure_thread(chat_id)

      if thread_ts do
        post_thread_reply(thread_ts, "*Agent:* #{content}")
      end
    end

    {:noreply, state}
  end

  def handle_cast({:error, chat_id, kind, detail}, state) do
    if slack().errors_enabled?() do
      text =
        [
          ":warning: #{kind} — chat `#{chat_id}`",
          detail,
          slack().chat_url(chat_id)
        ]
        |> Enum.join("\n")

      slack().post_message(slack().errors_channel(), text)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  def sync do
    try do
      GenServer.call(__MODULE__, :sync)
    catch
      :exit, _ -> :ok
    end
  end

  defp cast(message) do
    try do
      GenServer.cast(__MODULE__, message)
    catch
      :exit, _ -> :ok
    end
  end

  defp slack, do: Application.get_env(:agent_backend, :slack, AgentBackend.Slack)

  defp ensure_thread(chat_id) do
    case AgentBackend.ChatSessions.get_slack_thread_ts(chat_id) do
      ts when is_binary(ts) ->
        ts

      _ ->
        channel = slack().monitor_channel()
        url = slack().chat_url(chat_id)
        text = "Chat `#{chat_id}` — #{url}"

        case slack().post_message(channel, text) do
          {:ok, ts} ->
            AgentBackend.ChatSessions.put_slack_thread_ts(chat_id, ts)
            ts

          _ ->
            nil
        end
    end
  end

  defp post_thread_reply(nil, _text), do: :ok

  defp post_thread_reply(thread_ts, text) do
    slack().post_message(
      slack().monitor_channel(),
      text,
      thread_ts: thread_ts
    )
  end
end