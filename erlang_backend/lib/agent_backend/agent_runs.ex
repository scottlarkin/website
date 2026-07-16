defmodule AgentBackend.AgentRuns do
  @moduledoc """
  Single-flight agent runs plus live stream state for multi-tab sync.

  Only the agent Task mutates stream state via this process; LiveViews
  subscribe to PubSub snapshots and assign them absolutely (no rebroadcast).
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start a run with initial UI messages. Returns `:ok` or `{:error, :busy}`."
  def try_start(chat_id, run_id, messages)
      when is_binary(chat_id) and is_binary(run_id) and is_list(messages) do
    GenServer.call(__MODULE__, {:try_start, chat_id, run_id, messages})
  end

  @doc """
  Clear a run from the hub.

  Returns `:ok` if this call removed the entry, or `:already_done` if the run
  was already gone (cancelled or finished by another path).
  """
  def finish(chat_id, run_id) when is_binary(chat_id) and is_binary(run_id) do
    GenServer.call(__MODULE__, {:finish, chat_id, run_id})
  end

  @doc "Register the runner process so cancel can kill it."
  def set_runner(chat_id, run_id, pid)
      when is_binary(chat_id) and is_binary(run_id) and is_pid(pid) do
    GenServer.call(__MODULE__, {:set_runner, chat_id, run_id, pid})
  end

  @doc """
  Cancel an active run: settle messages, kill runner, free single-flight.

  Settled messages keep a non-empty partial assistant reply; drop an empty
  trailing assistant placeholder. Returns `{:ok, messages}` or `:ignore`.
  """
  def cancel(chat_id, run_id) when is_binary(chat_id) and is_binary(run_id) do
    GenServer.call(__MODULE__, {:cancel, chat_id, run_id})
  end

  def active?(chat_id) when is_binary(chat_id) do
    GenServer.call(__MODULE__, {:active?, chat_id})
  end

  def active?(_), do: false

  def current_run(chat_id) when is_binary(chat_id) do
    GenServer.call(__MODULE__, {:current_run, chat_id})
  end

  def current_run(_), do: nil

  @doc "Full live snapshot for multi-tab catch-up, or nil."
  def live_state(chat_id) when is_binary(chat_id) do
    GenServer.call(__MODULE__, {:live_state, chat_id})
  end

  def live_state(_), do: nil

  def append_token(chat_id, run_id, token)
      when is_binary(chat_id) and is_binary(run_id) and is_binary(token) do
    GenServer.call(__MODULE__, {:append_token, chat_id, run_id, token})
  end

  def reset_assistant(chat_id, run_id) when is_binary(chat_id) and is_binary(run_id) do
    GenServer.call(__MODULE__, {:reset_assistant, chat_id, run_id})
  end

  def hold_draft(chat_id, run_id) when is_binary(chat_id) and is_binary(run_id) do
    GenServer.call(__MODULE__, {:hold_draft, chat_id, run_id})
  end

  def set_status(chat_id, run_id, status) when is_binary(chat_id) and is_binary(run_id) do
    GenServer.call(__MODULE__, {:set_status, chat_id, run_id, status})
  end

  def set_error(chat_id, run_id, error_msg)
      when is_binary(chat_id) and is_binary(run_id) and is_binary(error_msg) do
    GenServer.call(__MODULE__, {:set_error, chat_id, run_id, error_msg})
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:try_start, chat_id, run_id, messages}, _from, state) do
    case Map.get(state, chat_id) do
      nil ->
        entry = %{
          run_id: run_id,
          messages: messages,
          agent_status: :generating,
          held_draft: nil,
          runner_pid: nil
        }

        {:reply, :ok, Map.put(state, chat_id, entry)}

      %{run_id: ^run_id} = entry ->
        {:reply, :ok, Map.put(state, chat_id, %{entry | messages: messages})}

      _other ->
        {:reply, {:error, :busy}, state}
    end
  end

  def handle_call({:finish, chat_id, run_id}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id} ->
        {:reply, :ok, Map.delete(state, chat_id)}

      _ ->
        {:reply, :already_done, state}
    end
  end

  def handle_call({:set_runner, chat_id, run_id, pid}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id} = entry ->
        {:reply, :ok, Map.put(state, chat_id, %{entry | runner_pid: pid})}

      _ ->
        {:reply, :ignore, state}
    end
  end

  def handle_call({:cancel, chat_id, run_id}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id} = entry ->
        messages = settle_cancelled_messages(entry.messages)
        kill_runner(entry[:runner_pid])
        {:reply, {:ok, messages}, Map.delete(state, chat_id)}

      _ ->
        {:reply, :ignore, state}
    end
  end

  def handle_call({:active?, chat_id}, _from, state) do
    {:reply, Map.has_key?(state, chat_id), state}
  end

  def handle_call({:current_run, chat_id}, _from, state) do
    run_id =
      case Map.get(state, chat_id) do
        %{run_id: id} -> id
        _ -> nil
      end

    {:reply, run_id, state}
  end

  def handle_call({:live_state, chat_id}, _from, state) do
    {:reply, Map.get(state, chat_id), state}
  end

  def handle_call({:append_token, chat_id, run_id, token}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id, messages: messages} = entry ->
        messages = append_to_last_assistant(messages, token)
        entry = %{entry | messages: messages, held_draft: nil}
        {:reply, {:ok, snapshot(entry)}, Map.put(state, chat_id, entry)}

      _ ->
        {:reply, :ignore, state}
    end
  end

  def handle_call({:reset_assistant, chat_id, run_id}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id, messages: messages} = entry ->
        messages = clear_last_assistant(messages)
        entry = %{entry | messages: messages}
        {:reply, {:ok, snapshot(entry)}, Map.put(state, chat_id, entry)}

      _ ->
        {:reply, :ignore, state}
    end
  end

  def handle_call({:hold_draft, chat_id, run_id}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id, messages: messages} = entry ->
        held =
          case List.last(messages) do
            %{role: "assistant", content: c} when is_binary(c) and c != "" -> c
            _ -> nil
          end

        entry = %{entry | held_draft: held, agent_status: :revising}
        {:reply, {:ok, snapshot(entry)}, Map.put(state, chat_id, entry)}

      _ ->
        {:reply, :ignore, state}
    end
  end

  def handle_call({:set_status, chat_id, run_id, status}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id} = entry ->
        entry = %{entry | agent_status: status}
        {:reply, {:ok, snapshot(entry)}, Map.put(state, chat_id, entry)}

      _ ->
        {:reply, :ignore, state}
    end
  end

  def handle_call({:set_error, chat_id, run_id, error_msg}, _from, state) do
    case Map.get(state, chat_id) do
      %{run_id: ^run_id, messages: messages} = entry ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        messages =
          case List.last(messages) do
            %{role: "assistant"} = last ->
              updated =
                last
                |> Map.put(:content, error_msg)
                |> Map.put(:error, true)
                |> Map.put(:timestamp, now)

              List.replace_at(messages, length(messages) - 1, updated)

            _ ->
              messages ++
                [
                  %{
                    role: "assistant",
                    content: error_msg,
                    timestamp: now,
                    error: true
                  }
                ]
          end

        entry = %{entry | messages: messages, agent_status: nil, held_draft: nil}
        {:reply, {:ok, snapshot(entry)}, Map.put(state, chat_id, entry)}

      _ ->
        {:reply, :ignore, state}
    end
  end

  defp kill_runner(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp kill_runner(_), do: :ok

  defp settle_cancelled_messages(messages) when is_list(messages) do
    case List.last(messages) do
      %{role: "assistant", content: c} = last when is_binary(c) and c != "" ->
        updated = Map.delete(last, :error)
        List.replace_at(messages, length(messages) - 1, updated)

      %{role: "assistant", content: c} when c in [nil, ""] ->
        Enum.drop(messages, -1)

      %{role: "assistant"} ->
        Enum.drop(messages, -1)

      _ ->
        messages
    end
  end

  defp snapshot(entry) do
    %{
      run_id: entry.run_id,
      messages: entry.messages,
      agent_status: entry.agent_status,
      held_draft: entry.held_draft,
      is_loading: true
    }
  end

  defp append_to_last_assistant(messages, token) do
    messages = ensure_trailing_assistant(messages)
    last_idx = length(messages) - 1
    last = List.last(messages)

    updated =
      last
      |> Map.put(:content, (last.content || "") <> token)
      |> Map.delete(:error)

    List.replace_at(messages, last_idx, updated)
  end

  defp clear_last_assistant(messages) do
    messages = ensure_trailing_assistant(messages)
    last_idx = length(messages) - 1
    last = List.last(messages)

    updated = last |> Map.put(:content, "") |> Map.delete(:error)
    List.replace_at(messages, last_idx, updated)
  end

  defp ensure_trailing_assistant([]) do
    [%{role: "assistant", content: "", timestamp: iso_now()}]
  end

  defp ensure_trailing_assistant(messages) do
    case List.last(messages) do
      %{role: "assistant"} -> messages
      _ -> messages ++ [%{role: "assistant", content: "", timestamp: iso_now()}]
    end
  end

  defp iso_now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
