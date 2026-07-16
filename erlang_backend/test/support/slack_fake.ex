defmodule AgentBackend.Slack.Fake do
  @moduledoc false

  @table :agent_backend_slack_fake

  def setup do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ok
    end

    reset()
  end

  def reset do
    ensure_table()
    :ets.insert(@table, {:enabled, true})
    :ets.insert(@table, {:errors_enabled, true})
    :ets.insert(@table, {:posts, []})
    :ets.insert(@table, {:ts_seq, 0})
  end

  def set_enabled(flag) when is_boolean(flag) do
    ensure_table()
    :ets.insert(@table, {:enabled, flag})
  end

  def set_errors_enabled(flag) when is_boolean(flag) do
    ensure_table()
    :ets.insert(@table, {:errors_enabled, flag})
  end

  def enabled? do
    ensure_table()
    :ets.lookup_element(@table, :enabled, 2)
  end

  def errors_enabled? do
    ensure_table()
    :ets.lookup_element(@table, :errors_enabled, 2)
  end

  def monitor_channel, do: "C_MONITOR"
  def errors_channel, do: "C_ERRORS"

  def chat_url(chat_id), do: "http://localhost:4002/c/#{chat_id}"

  def post_message(channel, text, opts \\ []) do
    ensure_table()
    thread_ts = Keyword.get(opts, :thread_ts)
    seq = :ets.update_counter(@table, :ts_seq, 1)
    ts = "ts.#{seq}"

    posts = :ets.lookup_element(@table, :posts, 2)

    entry = %{
      channel: channel,
      text: text,
      thread_ts: thread_ts,
      ts: ts
    }

    :ets.insert(@table, {:posts, [entry | posts]})
    {:ok, ts}
  end

  def posts do
    ensure_table()
    :ets.lookup_element(@table, :posts, 2) |> Enum.reverse()
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> setup()
      _ -> :ok
    end
  end
end
